module Gen.Route exposing
    ( Route(..)
    , fromUrl
    , toHref
    )

import Gen.Params.About
import Gen.Params.Home_
import Gen.Params.Login
import Gen.Params.NotFound
import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), Parser)


type Route
    = About
    | Home_
    | Login
    | NotFound


fromUrl : Url -> Route
fromUrl =
    Parser.parse (Parser.oneOf routes) >> Maybe.withDefault NotFound


routes : List (Parser (Route -> a) a)
routes =
    [ Parser.map Home_ Gen.Params.Home_.parser
    , Parser.map About Gen.Params.About.parser
    , Parser.map Login Gen.Params.Login.parser
    , Parser.map NotFound Gen.Params.NotFound.parser
    ]


toHref : Route -> String
toHref route =
    let
        joinAsHref : List String -> String
        joinAsHref segments =
            "/" ++ String.join "/" segments
    in
    case route of
        About ->
            joinAsHref [ "about" ]
    
        Home_ ->
            joinAsHref []
    
        Login ->
            joinAsHref [ "login" ]
    
        NotFound ->
            joinAsHref [ "not-found" ]

