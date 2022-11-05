import zeitplanLogo from "../public/Zeitplan.png?as=webp&width:50";
import { Elm } from "./Main.elm";

let flags = {
    logo: zeitplanLogo
};

let app = Elm.Main.init({
    flags: flags,
    node: document.getElementById('zeitplan')
})

app.ports.saveKey.subscribe(v => {
    console.log(v);
})

