// Written in the D programming language.
/**
Simple Continuos Integration Server for GitHub.

Copyright: Copyright Kai Nacke 2016.

License: BSD

Authors: Kai Nacke

See: https://developer.github.com/guides/building-a-ci-server/
*/

import vibe.appmain;
import vibe.core.concurrency;
import vibe.core.core;
import vibe.core.file;
import vibe.core.log;
import vibe.core.task;
import vibe.data.json;
import vibe.http.log;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.operations;
import vibe.utils.string : stripUTF8Bom;
import vibe.http.server;

import std.functional : toDelegate;

import dcis.state;

class CIServerSettings
{
    ushort port = 8080;
    string[] bindAddresses;
    string webhookPath = "/github/webhook";
    uint parallelBuildLimit = 1;

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
        if (auto pv = "parallelBuildLimit" in json) parallelBuildLimit = pv.get!uint;
    }
}

static Task dispatcherTask;
static State state;

shared static this()
{
    // Create/load settings
    auto cisettings = new CIServerSettings;
    if (existsFile("settings.json"))
    {
        logInfo("Reading settings.json");
        auto data = readFileUTF8("settings.json");
        auto json = parseJson(data);
        cisettings.parseSettings(json);
    }

    // Load state
    state = State.load(Path("state.json"));
    if (state.sanitize())
        state.save();

    auto router = new URLRouter;
    router.post(cisettings.webhookPath, &webhook);
    router.get("/", &index);
    router.get("/details", &details);

    dispatcherTask = runTask(toDelegate(&runDispatcherTask), cisettings.parallelBuildLimit);

    auto settings = new HTTPServerSettings;
    settings.port = cisettings.port;
    settings.bindAddresses = cisettings.bindAddresses;
    listenHTTP(settings, router);
}

void index(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!("index.dt", state, req);
}

void details(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!("details.dt", req);
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
            cirun.title = req.json["head_commit"]["message"].get!string;
            cirun.author = req.json["head_commit"]["author"]["name"].get!string;
            cirun.committer = req.json["head_commit"]["committer"]["name"].get!string;
        }
        else if (eventType == "pull_request")
        {
            cirun.reproUrl = req.json["pull_request"]["repo"]["clone_url"].get!string;
            cirun.commitSha = req.json["pull_request"]["head"]["sha"].get!string;
            cirun.title = req.json["pull_request"]["title"].get!string;
            cirun.author = req.json["pull_request"]["user"]["login"].get!string; // FIXME
            cirun.committer = req.json["pull_request"]["user"]["login"].get!string; // FIXME
        }
        else
            enforceBadRequest(false, "You did something wrong!");
        logInfo("Repository URL: %s", cirun.reproUrl);
        logInfo("Commit SHA:     %s", cirun.commitSha);
        dispatcherTask.send(cirun);
    }
    logInfo("Body: %s", req.json.toPrettyString);
    res.writeBody("");
}

void runDispatcherTask(uint parallelBuildLimit)
{
    while (true)
    {
        CIRun cirun;
        receive(
            (CIRun msg)
            {
                logInfo("Received run");
                cirun = msg;
                cirun.status = Status.received;
            });

        logInfo("To execute:");
        logInfo("git clone %s", cirun.reproUrl);
        logInfo("git checkout %s", cirun.commitSha);
        state.add(cirun);
        state.save();
    }
}
