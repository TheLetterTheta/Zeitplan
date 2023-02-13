module Gen.Params.SignUp exposing (Params, parser)

import Url.Parser as Parser


type alias Params =
    ()


parser =
    Parser.s "sign-up"
