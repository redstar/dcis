import vibe.appmain;
import vibe.http.server;

class CIServerSettings
{
    ushort port = 8080;
    string[] bindAddresses;
    string webhookPath = "/github/webhook";

    this()
    {
        import vibe.http.server : HTTPServerSettings;
        auto defaultBindAddresses = (new HTTPServerSettings).bindAddresses;
        bindAddresses = defaultBindAddresses;
    }

    void parseSettings(Json json)
    {
        import std.conv;

        if (auto pv = "port" in json) port = pv.get!ushort;
        if (auto pa = "bindAddresses" in json)
        {
            bindAddresses = [];
            foreach (address; *pa)
                bindAddresses ~= address.get!string;
        }
        if (auto pv = "webhookPath" in json) webhookPath = pv.get!string;
    }
}

shared static this()
{
    auto cisettings = new CIServerSettings;
    if (existsFile("settings.json"))
    {
        auto data = stripUTF8Bom(cast(string)openFile("settings.json").readAll());
        auto json = parseJson(data);
        cisettings.parseSettings(json);
    }

    auto router = new URLRouter;
    router.post(cisettings.webhookPath, &webhook);

    auto settings = new HTTPServerSettings;
    settings.port = cisettings.port;
    settings.bindAddresses = cisettings.bindAddresses;
    listenHTTP(settings, router);
}

void webhook(HTTPServerRequest req, HTTPServerResponse res)
{
    enforceBadRequest("X-GitHub-Event" in req.headers, "No GitHub event");
    string eventType = req.headers["X-GitHub-Event"]);
    enforceBadRequest(eventType == "push" || eventType == "pull_request", "Only GitHub event types push and pull_request are valid");

    logInfo("Event: %s", eventType);
    logInfo("Body: %s", req.json.toPrettyString);
    res.writeBody("");
}
