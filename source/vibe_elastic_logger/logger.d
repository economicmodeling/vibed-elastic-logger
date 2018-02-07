module vibe_elastic_logger.logger;

import std.algorithm.iteration : each, map;
import std.stdio;
import vibe.core.log : Logger, LogLine, LogLevel;
import std.array : appender;
import core.time : Duration;
import std.datetime : Clock, SysTime;

private alias MessageBuffer = typeof(appender!(char[])());

// Bypass to!string for log levels because we look them up frequently
private immutable string[LogLevel.max + 1] levelToString;

private string escapeChars(char ch) pure nothrow @safe
{
    switch (ch)
    {
    case '"':
        return `\"`;
    default:
        return () @trusted { return cast(string)[ch]; }();
    }
}

private void putEscapedString(ref typeof(appender!string()) buffer, const(char)[] str) @safe
{
    import std.utf : byCodeUnit;

    str.byCodeUnit().map!(ch => escapeChars(ch)).each!(s => buffer.put(s));
}

shared static this()
{
    levelToString[LogLevel.trace] = "trace";
    levelToString[LogLevel.debugV] = "debugVerbose";
    levelToString[LogLevel.debug_] = "debug";
    levelToString[LogLevel.diagnostic] = "diagnostic";
    levelToString[LogLevel.info] = "info";
    levelToString[LogLevel.warn] = "warn";
    levelToString[LogLevel.error] = "error";
    levelToString[LogLevel.critical] = "critical";
    levelToString[LogLevel.fatal] = "fatal";
    levelToString[LogLevel.none] = "none";
}

/**
 * An IndexCreator is a delegate that calculates the ElasticSearch index that
 * the logger should log to.
 */
alias IndexCreator = string delegate() @safe;

/**
 * ElasticSearch server connection information.
 */
struct ElasticInfo
{
    /// Host name for the ElasticSearch server.
    string hostName;
    // Port for connecting to the ElasticSearch server.
    ushort portNumber = 9200;
    // For the "type" that the log messages will be given within an index.
    string typeName;
}

/**
 * ElasticSearch logger implementation.
 *
 * Messages are queued and written to the server when any of the following
 * conditions are met:
 * $(UL
 * $(LI The message queue is full.)
 * $(LI The message to be logged has a LogLevel of `critical` or higher.)
 * $(LI A message is queued to be logged, and more time than the `maxLogInterval`
 *     constructor argument has passed.)
 * $(LI The logger is asked to log the message "Main thread exiting".)
 * )
 *
 * The name of the index that the logger writes messages to is determined by a
 * function (the `indexCreator` constructor argument). This usually returns an
 * index name based off of the current time.
 */
class ElasticLogger : Logger
{
    /**
     * Params:
     *     elasticInfo = Connection information to use when logging messages.
     *     indexCreator = A function that will return the name of the index to
     *         log to.
     *     maxLogInterval = If a log message is received and more than this
     *         amount of time has passed since the last flush, trigger a flush
     *         regardless of the remaining space in the buffer.
     *     messageQueueSize = Number of log messages to queue between writes to
     *         ElasticSearch.
     */
    this(const ElasticInfo elasticInfo, const IndexCreator indexCreator,
            const Duration maxLogInterval, const size_t messageQueueSize)
    {
        this.indexCreator = indexCreator;
        this.maxLogInterval = maxLogInterval;
        this.entries = new LogEntry[](messageQueueSize);
        this.multilineLogger = true;
        this.minLevel = LogLevel.trace;
        this.lastFlushTime = Clock.currTime();
        this.elasticInfo = elasticInfo;
        this.logQueueIndex = 0;
        this.flushing = false;
    }

    override void beginLine(ref LogLine line) @safe
    {
        if (flushing)
            return;

        LogEntry* l = &entries[logQueueIndex];
        l.module_ = line.mod;
        l.function_ = line.func;
        l.file = line.file;
        l.line = line.line;
        l.lLevel = line.level;
        l.level = levelToString[line.level];
        l.fiberID = line.fiberID;
        l.time = line.time.toISOExtString();
        l.buffer.clear();
    }

    override void endLine() @safe
    {
        if (flushing)
            return;

        immutable r = logQueueIndex;
        logQueueIndex++;
        if (logQueueIndex == entries.length || entries[r].lLevel >= LogLevel.critical
                || (entries[r].lLevel == LogLevel.diagnostic
                    && entries[r].buffer.data == "Main thread exiting")
                || lastFlushTime + maxLogInterval < Clock.currTime())
            flush();
    }

    override void put(scope const(char)[] text) @safe
    {
        if (flushing)
            return;

        entries[logQueueIndex].buffer.put(text);
    }

private:

    static struct LogEntry
    {
        string module_;
        string function_;
        string file;
        int line;
        LogLevel lLevel;
        string level;
        uint fiberID;
        string time;
        MessageBuffer buffer;
    }

    void flush() @safe
    {
        import std.conv : to;
        import std.format : format;
        import vibe.http.client : requestHTTP, HTTPClientRequest, HTTPClientResponse, HTTPMethod;

        flushing = true;
        scope(exit) flushing = false;

        immutable elasticIndex = indexCreator();
        immutable url = format!"http://%s:%d/%s/%s/_bulk"(elasticInfo.hostName,
                elasticInfo.portNumber, elasticIndex, elasticInfo.typeName);
        version(debug_elastic_logger)
        {
            () @trusted { stderr.writeln("\033[01;33m", url, "\033[0m"); }();
        }
        auto requestBody = appender!string();
        foreach (ref entry; entries[0 .. logQueueIndex])
        {
            requestBody.put(`{"index": {}}`);
            requestBody.put("\n");
            requestBody.put(`{"message":"`);
            requestBody.putEscapedString(entry.buffer.data);
            requestBody.put(`","module":"`);
            requestBody.put(entry.module_);
            requestBody.put(`","function":"`);
            requestBody.putEscapedString(entry.function_);
            requestBody.put(`","file":"`);
            requestBody.putEscapedString(entry.file);
            requestBody.put(`","line":"`);
            requestBody.put(entry.line.to!string());
            requestBody.put(`","level":"`);
            requestBody.put(entry.level);
            requestBody.put(`","fiberID":"`);
            requestBody.put(entry.fiberID.to!string());
            requestBody.put(`","time":"`);
            requestBody.put(entry.time);
            requestBody.put(`"}`);
            requestBody.put("\n");
        }

        version(debug_elastic_logger)
        {
            () @trusted { stderr.writeln("\033[01;33m", requestBody.data, "\033[0m"); }();
        }

        logQueueIndex = 0;
        this.lastFlushTime = Clock.currTime();
        requestHTTP(url,
            (scope request) {
                request.method = HTTPMethod.POST;
                request.writeBody(cast(ubyte[]) requestBody.data, "application/x-ndjson");
            },
            (scope response) {
                response.dropBody();
            });
    }


    // See constructor docs
    const IndexCreator indexCreator;
    // See constructor docs
    const Duration maxLogInterval;
    // See constructor docs
    const ElasticInfo elasticInfo;
    // Time that the last flush happened
    SysTime lastFlushTime;
    // Message queue
    LogEntry[] entries;
    // Index into the `entries` buffer.
    size_t logQueueIndex;
    // True if the logger is currently flushing log info to the server. Prevents
    // the HTTP request code from causing an infinite recursion.
    bool flushing;
}
