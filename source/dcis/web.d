// Written in the D programming language.
module dcis.web;

import vibe.web.web;

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
        CIRun cirun;
        foreach(c; state)
        {
            if (c.id == _id)
            {
                cirun = c;
                break;
            }
        }

        render!("details.dt", cirun);
    }
}
