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

        // Wait for the build to start
        logInfo("Wait for state");
        auto build = state.getBuild(_id);
        while (true)
        {
            import core.atomic;
            logInfo("Wait...");
            atomicFence(); // Overkill
            auto status = build.status;
            if (status > Status.received)
                break;
            sleep(500.msecs);
        }

        // Wait until the report file is written
        logInfo("Wait for file");
        string fileName = "/tmp/dcis." ~ to!string(_id) ~ ".report";
        while (!existsFile(fileName)) {
            logInfo("Wait...");
            sleep(200.msecs);
        }
        
        // Transmit the file
        logInfo("Sending file...");
        auto file = openFile(Path(fileName), FileMode.read);
        scope(exit) file.close();
        while (socket.connected)
        {
            ubyte[2048] buf;

            if (file.leastSize() > 0)
            {
                auto size = min(file.leastSize(), buf.length);
                logInfo("Reading %d bytes", size);
                if (size > 0)
                {
                    file.read(buf[0..size]);
                    socket.send(cast(string)buf[0..size]);
                }
            }
            else
            {
                import core.atomic;
                atomicFence(); // Overkill
                if (build.status >= Status.finished)
                    break;
                sleep(200.msecs);
            }
        }
        socket.close();
        logInfo("Sending log file complete");
    }
}
