import vibe.d;

shared static this()
{
    auto router = new URLRouter;
    router.post("github/webhook", &webhook);

    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    settings.bindAddresses = ["172.18.1.3", "127.0.0.1"];
    listenHTTP(settings, router);
}

void webhook(HTTPServerRequest req, HTTPServerResponse res)
{
    if ("X-GitHub-Event" in req.headers)
        logInfo("Event: %s", req.headers["X-GitHub-Event"]);
    logInfo("Body: %s", req.json.toPrettyString);
    res.writeBody("");
}
