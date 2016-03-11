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

import std.container.array;
import std.functional : toDelegate;

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

shared static this()
{
    auto cisettings = new CIServerSettings;
    if (existsFile("settings.json"))
    {
        logInfo("Reading settings.json");
        auto data = readFileUTF8("settings.json");
        auto json = parseJson(data);
        cisettings.parseSettings(json);
    }

    auto router = new URLRouter;
    router.post(cisettings.webhookPath, &webhook);
    router.get("/", &index);

    dispatcherTask = runTask(toDelegate(&runDispatcherTask), cisettings.parallelBuildLimit);

    auto settings = new HTTPServerSettings;
    settings.port = cisettings.port;
    settings.bindAddresses = cisettings.bindAddresses;
    listenHTTP(settings, router);
}

void index(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!("index.dt", req);
}

enum Status { received, running, finished, finishedWithError };

struct CIRun
{
    string reproUrl;
    string commitSha;
    string title;
    string author;
    string committer;
    Status status;
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

/*
- Request ->
    - status, title, authot
      status: received, inWork, finished, finishedError

- Put Request in slist first
- Serialize list to disk

*/

void runDispatcherTask(uint parallelBuildLimit)
{
    State state = State.load(Path("state.json"));
    if (state.sanitize())
        state.save();

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

class State
{
    Array!CIRun state;
    Path path;
    
    private this(Array!CIRun state, Path path)
    {
        this.state = state;
        this.path = path;
    }
    
    static load(Path path)
    {
        if (existsFile(path))
        {
            auto data = readFileUTF8(path);
            auto json = parseJson(data);
            return new State(deserializeJson!(Array!CIRun)(json), path);
        }
        return new State(Array!CIRun(), path);
    }
    
    void save()
    {
        auto json = serializeToJson(state);
        writeFileUTF8(path, json.toString());
    }

    bool sanitize()
    {
        bool changed = false;

        foreach (ref s; state)
        {
            if (s.status == Status.running)
            {
                s.status = Status.received;
                changed = true;
            }
        }
        return changed;
    }
    
    void add(CIRun cirun)
    {
        state.insert(cirun);
    }
}
