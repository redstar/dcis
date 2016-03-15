// Written in the D programming language.
module dcis.web;

import vibe.core.core;
import vibe.core.file;
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

        string fileName = "reports/dcis." ~ to!string(_id) ~ ".report";
        while (!existsFile(fileName)) {
            sleep(200.msecs);
        }
        
        auto file = openFile(Path(fileName), FileMode.read);
        while (socket.connected)
        {
            ubyte[2048] buf;

            if (file.dataAvailableForRead)
            {
                auto size = min(file.leastSize(), buf.length);
                file.read(buf[0..size]);
                socket.send(cast(string)buf[0..size]);
            }
            else
                sleep(200.msecs);
        }
    }
}
