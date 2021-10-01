module View exposing (NavMsg(..), View, button, container, content, footer, linkToElement, map, none, placeholder, toBrowserDocument, zeitplanNav)

import Browser
import FontAwesome.Brands exposing (facebook, github)
import FontAwesome.Icon as Icon
import FontAwesome.Solid exposing (heart, music)
import Gen.Route as Route
import Html exposing (Attribute, Html, a, div, i, img, nav, p, span, strong, text)
import Html.Attributes exposing (attribute, class, classList, height, href, src, target, width)
import Html.Events exposing (onClick)
import Shared


role : String -> Attribute msg
role name =
    attribute "role" name


ariaLabel : String -> Attribute msg
ariaLabel name =
    attribute "aria-label" name


ariaHidden : Bool -> Attribute msg
ariaHidden hide =
    if hide then
        attribute "aria-hidden" "true"

    else
        attribute "aria-hidden" "false"


logo : String -> Html msg
logo source =
    img
        [ class "m-1"
        , src source
        , height 50
        , width 30
        ]
        []


container : List (Attribute msg) -> List (Html msg) -> Html msg
container attrs children =
    div (class "container" :: attrs) children


button : List (Attribute msg) -> List (Html msg) -> Html msg
button attrs children =
    Html.button (class "button" :: attrs) children


content : List (Attribute msg) -> List (Html msg) -> Html msg
content attrs children =
    div (class "content" :: attrs) children


footer : Html msg
footer =
    Html.footer [ class "footer" ]
        [ content [ class "has-text-centered has-text-weight-bold" ]
            [ p [] [ text "This project was made possible thanks to Professor Victor Drescher at Southeastern Louisiana University." ]
            , div [ class "columns" ]
                [ div [ class "column" ]
                    [ p [ class "subtitle" ]
                        [ text "If you found Zeitplan useful"
                        , div [ class "mt-3 is-flex is-justify-content-space-around" ]
                            [ a [ class "button", target "_blank", href "https://github.com/sponsors/TheLetterTheta" ]
                                [ span [ class "icon" ]
                                    [ Icon.viewIcon heart
                                    ]
                                , span [] [ text "Sponsoring the project" ]
                                ]
                            , a [ class "button", href "https://github.com/TheLetterTheta/Zeitplan", target "_blank" ]
                                [ span [ class "icon" ]
                                    [ Icon.viewIcon github
                                    ]
                                , span [] [ text "Suggest an edit" ]
                                ]
                            ]
                        ]
                    ]
                , div [ class "column" ]
                    [ p [ class "subtitle" ]
                        [ text "You can also support Drescher Music by visiting" ]
                    , div [ class "mt-3 is-flex is-justify-content-space-around" ]
                        [ a [ class "button", target "_blank", href "https://www.facebook.com/DrescherMusic" ]
                            [ span [ class "icon" ]
                                [ Icon.viewIcon facebook
                                ]
                            , span [] [ text "Facebook" ]
                            ]
                        , a [ class "button", href "https://dreschermusic.com", target "_blank" ]
                            [ span [ class "icon" ]
                                [ Icon.viewIcon music
                                ]
                            , span [] [ text "DrescherMusic.com" ]
                            ]
                        ]
                    ]
                ]
            ]
        ]


type NavMsg
    = ToggleHamburger
    | Logout


zeitplanNav :
    { logo : String
    , shared : Shared.Model
    }
    -> Html NavMsg
zeitplanNav settings =
    nav
        [ class "navbar is-primary"
        , role "navigation"
        , ariaLabel "main navigation"
        ]
        [ div [ class "navbar-brand is-flex is-align-content-space-between" ]
            [ div [ class "navbar-item is-flex-grow-1" ]
                [ logo settings.shared.logo
                ]
            , Html.button
                [ class "navbar-burger is-flex-shrink-1"
                , classList <|
                    [ ( "is-active", settings.shared.expandHamburger ) ]
                , ariaLabel "menu"
                , onClick ToggleHamburger
                ]
                [ span [ ariaHidden True ] []
                , span [ ariaHidden True ] []
                , span [ ariaHidden True ] []
                ]
            ]
        , div
            [ class "navbar-menu"
            , classList <|
                [ ( "is-active", settings.shared.expandHamburger ) ]
            ]
            [ div [ class "navbar-start" ]
                [ a
                    [ class "navbar-item is-size-4", href (Route.toHref Route.Home_) ]
                    [ text "Home" ]
                , a
                    [ class "navbar-item is-size-4", href (Route.toHref Route.About) ]
                    [ text "About" ]
                ]
            , div [ class "navbar-end" ]
                [ div [ class "navbar-item" ]
                    [ button
                        [ class "is-primary"
                        , onClick Logout
                        ]
                        [ text "Logout"
                        ]
                    ]
                ]
            ]
        ]


linkToElement : String -> List (Html msg) -> Html msg
linkToElement linkId children =
    a [ href <| "#" ++ linkId ]
        children


type alias View msg =
    { title : String
    , body : List (Html msg)
    }


placeholder : String -> View msg
placeholder str =
    { title = str
    , body = [ Html.text str ]
    }


none : View msg
none =
    placeholder ""


map : (a -> b) -> View a -> View b
map fn view =
    { title = view.title
    , body = List.map (Html.map fn) view.body
    }


toBrowserDocument : View msg -> Browser.Document msg
toBrowserDocument view =
    { title = view.title
    , body = view.body
    }
