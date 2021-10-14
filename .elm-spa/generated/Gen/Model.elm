module Gen.Model exposing (Model(..))

import Gen.Params.About
import Gen.Params.Home_
import Gen.Params.Login
import Gen.Params.NotFound
import Pages.About
import Pages.Home_
import Pages.Login
import Pages.NotFound


type Model
    = Redirecting_
    | About Gen.Params.About.Params Pages.About.Model
    | Home_ Gen.Params.Home_.Params Pages.Home_.Model
    | Login Gen.Params.Login.Params
    | NotFound Gen.Params.NotFound.Params

