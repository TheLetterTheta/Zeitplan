module Gen.Msg exposing (Msg(..))

import Gen.Params.About
import Gen.Params.Home_
import Gen.Params.Login
import Gen.Params.PaymentConfirmation
import Gen.Params.Pricing
import Gen.Params.Schedule
import Gen.Params.NotFound
import Pages.About
import Pages.Home_
import Pages.Login
import Pages.PaymentConfirmation
import Pages.Pricing
import Pages.Schedule
import Pages.NotFound


type Msg
    = About Pages.About.Msg
    | Home_ Pages.Home_.Msg
    | Login Pages.Login.Msg
    | PaymentConfirmation Pages.PaymentConfirmation.Msg
    | Pricing Pages.Pricing.Msg
    | Schedule Pages.Schedule.Msg

