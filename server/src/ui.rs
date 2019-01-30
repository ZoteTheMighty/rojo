use typed_html::{
    dom::{Node, DOMTree},
    elements::FlowContent,
    html,
    text,
};

use crate::live_session::LiveSession;

const DOCTYPE: &str = "<!doctype html>";
static CSS: &str = include_str!("../assets/style.css");

pub fn render(live_session: &LiveSession) -> String {
    format!("{}\n{}", DOCTYPE, render_main(live_session).to_string())
}

fn render_main(live_session: &LiveSession) -> DOMTree<String> {
    html!(
        <html>
            <head>
                <title>"Rojo Live Session"</title>
                <style>{ text!("{}", CSS) }</style>
            </head>
            <body>
                { render_body(live_session) }
            </body>
        </html>
    )
}

fn render_body(live_session: &LiveSession) -> Box<impl FlowContent<String>> {
    html!(
        <h1>"Hello, world!"</h1>
    )
}