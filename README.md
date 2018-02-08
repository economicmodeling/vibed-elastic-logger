# vibed-elastic-logger
ElasticSearch logger implementation for Vibe.d

## Example

```d
void main()
{
    import vibe.core.log : logInfo, registerLogger;
    import vibe_elastic_logger : ElasticInfo, ElasticLogger;
    import core.time : dur;

    string generateIndex() @safe
    {
        import std.datetime : Clock;
        import std.format : format;

        auto now = Clock.currTime();
        return format!"vibe_logger_test_%04d_%02d"(now.year, now.month);
    }

    ElasticInfo info;
    info.hostName = "localhost";
    info.typeName = "messages";
    info.portNumber = 9200;
    auto l = cast(shared) new ElasticLogger(info, &generateIndex, dur!"seconds"(5), 30);
    registerLogger(l);
}
```
