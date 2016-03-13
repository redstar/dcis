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

    void getDetails()
    {
        render!("details.dt");
    }
}
