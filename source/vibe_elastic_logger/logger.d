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
 *
 */
class ElasticLogger : Logger
{
    /**
     * Params:
     *     indexCreator = A function that will return the name of the index to
     *         log to.
     *     maxLogInterval = If a log message is received and more than this
     *         amount of time has passed since the last flush, trigger a flush
     *         regardless of the remaining space in the buffer.
     *     bufferSize = Number of log messages to queue between writes to
     *         ElasticSearch.
     */
    this(const string elasticUrl, const IndexCreator indexCreator,
            const Duration maxLogInterval, const size_t bufferSize)
    {
        this.indexCreator = indexCreator;
        this.maxLogInterval = maxLogInterval;
        this.entries = new LogEntry[](bufferSize);
        this.multilineLogger = true;
        this.minLevel = LogLevel.trace;
        this.lastFlushTime = Clock.currTime();
        this.elasticUrl = elasticUrl;
        this.logBufferIndex = 0;
    }

    override void beginLine(ref LogLine line) @safe
    {
        LogEntry* l = &entries[logBufferIndex];
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
        immutable r = logBufferIndex;
        logBufferIndex++;
        if (logBufferIndex == entries.length || entries[r].lLevel >= LogLevel.critical
                || entries[r].buffer.data == "Main thread exiting"
                || lastFlushTime + maxLogInterval < Clock.currTime())
            flush();
    }

    override void put(scope const(char)[] text) @safe
    {
        entries[logBufferIndex].buffer.put(text);
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
        import std.utf : byCodeUnit;

        immutable elasticIndex = indexCreator();
        immutable url = elasticUrl ~ elasticIndex ~ "/messages/_bulk";
        () @trusted{ stderr.writeln("\033[01;33m", url, "\033[0m"); }();
        auto requestBody = appender!string();
        foreach (ref entry; entries[0 .. logBufferIndex])
        {
            requestBody.put(`{"index": {}}`);
            requestBody.put("\n");
            requestBody.put(`{"message": "`);
            entry.buffer.data.byCodeUnit().map!((char ch) @safe {
                    switch (ch) {
                        case '"': return `\"`;
                        default: return () @trusted { return cast(string) [ch]; }();
                    }
                })
                .each!(s => requestBody.put(s));
            requestBody.put(`"}`);
            requestBody.put("\n");
        }
        () @trusted{ stderr.writeln("\033[01;33m", requestBody.data, "\033[0m"); }();
        logBufferIndex = 0;
        this.lastFlushTime = Clock.currTime();
    }

    LogEntry[] entries;
    const IndexCreator indexCreator;
    const Duration maxLogInterval;
    SysTime lastFlushTime;
    const string elasticUrl;
    size_t logBufferIndex;
}
