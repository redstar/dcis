import vibe.appmain;
import vibe.core.file;
import vibe.core.log;
import vibe.data.json;
import vibe.http.log;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.operations;
import vibe.utils.string : stripUTF8Bom;

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
        logInfo("Reading settings.json");
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

struct CIRun
{
    string reproUrl;
    string commitSha;
}

void webhook(HTTPServerRequest req, HTTPServerResponse res)
{
    enforceBadRequest("X-GitHub-Event" in req.headers, "No GitHub event");
    string eventType = req.headers["X-GitHub-Event"];
    enforceBadRequest(eventType == "push" || eventType == "pull_request" || eventType == "ping",
                      "Only GitHub event types push, pull_request and ping are valid");

    logInfo("Received event: %s", eventType);
    if (eventType != "ping")
    {
        CIRun cirun;
        if (eventType == "push")
        {
            cirun.reproUrl = req.json["repository"]["clone_url"].get!string;
            cirun.commitSha = req.json["after"].get!string;
        }
        else if (eventType == "pull_request")
        {
            cirun.reproUrl = req.json["pull_request"]["repo"]["clone_url"].get!string;
            cirun.commitSha = req.json["pull_request"]["head"]["sha"].get!string;
        }
        else
            enforceBadRequest(false, "You did something wrong!");
        logInfo("Repository URL: %s", cirun.reproUrl);
        logInfo("Commit SHA:     %s", cirun.commitSha);
    }
    logInfo("Body: %s", req.json.toPrettyString);
    res.writeBody("");
}
