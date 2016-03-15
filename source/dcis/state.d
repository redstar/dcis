// Written in the D programming language.
module dcis.state;

import vibe.core.core;
import vibe.core.file;
import vibe.data.json;
import vibe.stream.operations;

import std.array;
import std.container.array;

enum Status { received, running, finished, finishedWithError };

struct Build
{
    uint id;
    string reproUrl;
    string reproName;
    string commitSha;
    string title;
    string author;
    string committer;
    Status status;
}

class State
{
private:
    Array!Build builds;
    Path path;
    uint nextId;
    
    this(Build[] builds, Path path)
    {
        import std.algorithm.comparison : max;

        this.builds = Array!Build(builds);
        this.path = path;
        this.nextId = 0;
        foreach (build; builds)
            this.nextId = max(this.nextId, build.id+1);
    }
    
public:
    alias Range = builds.Range;
    
    static load(Path path)
    {
        Build[] builds;
        if (existsFile(path))
        {
            auto data = readFileUTF8(path);
            auto json = parseJson(data);
            builds = deserializeJson!(Build[])(json);
        }
        return new State(builds, path);
    }
    
    void save()
    {
        auto json = serializeToJson(builds.array());
        writeFileUTF8(path, json.toString());
    }

    bool sanitize()
    {
        bool changed = false;

        foreach (ref build; builds)
        {
            if (build.status == Status.running)
            {
                build.status = Status.received;
                changed = true;
            }
        }
        return changed;
    }
    
    void add(ref Build build)
    {
        build.id = nextId++;
        builds.insert(build);
    }

    Range opSlice()
    {
        return builds.opSlice();
    }
}
