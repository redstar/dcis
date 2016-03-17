// Written in the D programming language.
module dcis.web;

import vibe.core.core;
import vibe.core.file;
import vibe.core.log;
import vibe.http.common;
import vibe.http.websockets;
import vibe.web.web;

import std.conv;

import dcis.state;

class WebApp
{
private:
    State state;

public:
    this(State state)
    {
        this.state = state;
    }

    @path("/")
    void getIndex()
    {
        auto state = this.state;
        render!("index.dt", state);
    }

    @path("/details/:id")
    void getDetails(int _id)
    {
        Build build;
        foreach(c; state)
        {
            if (c.id == _id)
            {
                build = c;
                break;
            }
        }

        render!("details.dt", build);
    }
    
    @path("/ws/:id")
    void getWS(int _id, scope WebSocket socket)
    {
        import core.time : msecs;

        enforceBadRequest(state.exists(_id));

        string dirName = "/tmp"; // FIXME
        string fileName = dirName ~ "/dcis." ~ to!string(_id) ~ ".report";

        // Wait until the report file is written
        logInfo("Wait for file");
        auto watcher = Path("/tmp").watchDirectory(false);
        DirectoryChange[] changes;
        watcher.readChanges(changes, 0.msecs);
        while (!existsFile(fileName)) {
            watcher.readChanges(changes);
        }
        
        // Transmit the file
        logInfo("Sending file...");
        auto file = openFile(Path(fileName), FileMode.read);
        scope(exit) file.close();
        while (socket.connected)
        {
            ubyte[2048] buf;

            auto leastSize = file.leastSize;
            logInfo("leastSize %d (%s)", leastSize, file.dataAvailableForRead);
            if (leastSize > 0)
            {
                auto size = min(leastSize, buf.length);
                logInfo("Reading %d bytes", size);
                if (size > 0)
                {
                    file.read(buf[0..size]);
                    socket.send(cast(string)buf[0..size]);
                }
            }
            else
            {
                if (state.getBuild(_id).status >= Status.finished)
                    break;
                logInfo("Wait for data");
                sleep(200.msecs);
            }
        }
        socket.close();
        logInfo("Sending log file complete");
    }
}
