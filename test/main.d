import vibe_elastic_logger;

void main()
{
    import vibe.core.log : logInfo, registerLogger;
    import vibe_elastic_logger : ElasticInfo, ElasticLogger;
    import core.time : dur;

    ElasticInfo info;
    info.hostName = "localhost";
    info.typeName = "messages";
    info.portNumber = 9200;
    auto l = cast(shared) new ElasticLogger(info, () => "vibe_logger_test", dur!"seconds"(5), 30);
    registerLogger(l);

    logInfo("Logger test message");
}
