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
import vibe.web.web;

import std.functional : toDelegate;

import dcis.state;
import dcis.web;

class CIServerSettings
{
    ushort port = 8080;
    string[] bindAddresses;
    string webhookPath = "/github/webhook";
    string buildCommand;
    string workDirectory = "/tmp";
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
        if (auto pv = "buildCommand" in json) buildCommand = pv.get!string;
        if (auto pv = "workDirectory" in json) workDirectory = pv.get!string;
        if (auto pv = "parallelBuildLimit" in json) parallelBuildLimit = pv.get!uint;
    }

    void logsettings(LogLevel level)()
    {
        log!level("Settings:");
        log!level("Port: %s", port);
        log!level("Bind addresses: %s", bindAddresses);
        log!level("Path for GitHub events: %s", webhookPath);
        log!level("Build command: %s", buildCommand);
        log!level("Working directory for build: %s", workDirectory);
        log!level("Max. number of parallel build: %d", parallelBuildLimit);
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
    cisettings.logsettings!(LogLevel.info)();

    // Load state
    state = State.load(Path("state.json"));
    if (state.sanitize())
        state.save();

    auto router = new URLRouter;
    router.post(cisettings.webhookPath, &webhook);
    router.registerWebInterface(new WebApp(state));

    DispatcherSettings disettings = {
        buildCommand: cisettings.buildCommand,
        workDirectory: cisettings.workDirectory,
        parallelBuildLimit: cisettings.parallelBuildLimit,
    };
    dispatcherTask = runTask(toDelegate(&runDispatcherTask), disettings);

    auto settings = new HTTPServerSettings;
    settings.port = cisettings.port;
    settings.bindAddresses = cisettings.bindAddresses;
    listenHTTP(settings, router);
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
            cirun.reproName = req.json["repository"]["name"].get!string;
            cirun.commitSha = req.json["after"].get!string;
            cirun.title = req.json["head_commit"]["message"].get!string;
            cirun.author = req.json["head_commit"]["author"]["name"].get!string;
            cirun.committer = req.json["head_commit"]["committer"]["name"].get!string;
        }
        else if (eventType == "pull_request")
        {
            cirun.reproUrl = req.json["pull_request"]["repo"]["clone_url"].get!string;
            cirun.reproName = req.json["pull_request"]["repo"]["clone_url"].get!string; // FIXME
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

struct DispatcherSettings
{
    string buildCommand;
    string workDirectory;
    uint parallelBuildLimit;
}

void runDispatcherTask(DispatcherSettings settings)
{
    int running = 0;
    int scheduled = 0;

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

        state.add(cirun);
        state.save();
        runWorkerTask(&runBuild, cirun, settings.buildCommand, settings.workDirectory);
    }
}


void runBuild(CIRun cirun, string buildCommand, string workDirectory)
{
    import std.file : mkdir, rmdirRecurse;
    import std.stdio;
    import std.process;

    auto report = File("/tmp/dcis."~to!string(cirun.id)~".report", "w+");
    auto nothing = File("/dev/null", "r");
    const(char[][]) args = [ buildCommand, cirun.reproUrl, cirun.reproName, cirun.commitSha];
    auto path = Path(joinPath(workDirectory, "dcis."~to!string(cirun.id)));
    path.normalize();
    auto directory = path.toNativeString();
    mkdir(directory);
    auto pid = spawnProcess(args, nothing, report, report, null, Config.suppressConsole, directory);
    auto rc = wait(pid);
    rmdirRecurse(directory);
}
