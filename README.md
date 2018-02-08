# vibed-elastic-logger
ElasticSearch logger implementation for Vibe.d

## Documentation

[Available online here](https://economicmodeling.github.io/vibed-elastic-logger/).

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

## Data Format

Here's an example of what a log message will look like in Elastic:
```json
...
      {
        "_index": "vibe_logger_test_2018_02",
        "_type": "messages",
        "_id": "AWFtxExgJY-mBsy0A_50",
        "_score": 1,
        "_source": {
          "message": "Main thread exiting",
          "module": "",
          "function": "",
          "file": "../../.dub/packages/vibe-d-0.8.2/vibe-d/core/vibe/core/core.d",
          "line": "1781",
          "level": "diagnostic",
          "fiberID": "0",
          "time": "2018-02-07T00:57:16.6429738Z"
        }
      },
...
```
