// Written in the D programming language.
module dcis.state;

import vibe.core.core;
import vibe.core.file;
import vibe.data.json;
import vibe.stream.operations;

import std.array;
import std.container.array;

enum Status { received, running, finished, finishedWithError };

struct CIRun
{
    uint id;
    string reproUrl;
    string commitSha;
    string title;
    string author;
    string committer;
    Status status;
}

class State
{
private:
    Array!CIRun state;
    Path path;
    uint nextId;
    
    this(CIRun[] ciruns, Path path)
    {
        import std.algorithm.comparison : max;

        this.state = Array!CIRun(ciruns);
        this.path = path;
        this.nextId = 0;
        foreach (cirun; ciruns)
            this.nextId = max(this.nextId, cirun.id+1);
    }
    
public:
    alias Range = state.Range;
    
    static load(Path path)
    {
        CIRun[] ciruns;
        if (existsFile(path))
        {
            auto data = readFileUTF8(path);
            auto json = parseJson(data);
            ciruns = deserializeJson!(CIRun[])(json);
        }
        return new State(ciruns, path);
    }
    
    void save()
    {
        auto json = serializeToJson(state.array());
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
    
    void add(ref CIRun cirun)
    {
        cirun.id = nextId++;
        state.insert(cirun);
    }

    Range opSlice()
    {
        return state.opSlice();
    }
}
