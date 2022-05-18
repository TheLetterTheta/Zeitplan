module Gen.Msg exposing (Msg(..))

import Gen.Params.About
import Gen.Params.Home_
import Gen.Params.Login
import Gen.Params.Pricing
import Gen.Params.SignUp
import Gen.Params.NotFound
import Pages.About
import Pages.Home_
import Pages.Login
import Pages.Pricing
import Pages.SignUp
import Pages.NotFound


type Msg
    = About Pages.About.Msg
    | Home_ Pages.Home_.Msg
    | Pricing Pages.Pricing.Msg
    | SignUp Pages.SignUp.Msg

