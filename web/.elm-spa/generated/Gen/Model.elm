module Gen.Model exposing (Model(..))

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


type Model
    = Redirecting_
    | About Gen.Params.About.Params Pages.About.Model
    | Home_ Gen.Params.Home_.Params Pages.Home_.Model
    | Login Gen.Params.Login.Params Pages.Login.Model
    | PaymentConfirmation Gen.Params.PaymentConfirmation.Params Pages.PaymentConfirmation.Model
    | Pricing Gen.Params.Pricing.Params Pages.Pricing.Model
    | Schedule Gen.Params.Schedule.Params Pages.Schedule.Model
    | NotFound Gen.Params.NotFound.Params

