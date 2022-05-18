module Gen.Model exposing (Model(..))

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


type Model
    = Redirecting_
    | About Gen.Params.About.Params Pages.About.Model
    | Home_ Gen.Params.Home_.Params Pages.Home_.Model
    | Login Gen.Params.Login.Params
    | Pricing Gen.Params.Pricing.Params Pages.Pricing.Model
    | SignUp Gen.Params.SignUp.Params Pages.SignUp.Model
    | NotFound Gen.Params.NotFound.Params

