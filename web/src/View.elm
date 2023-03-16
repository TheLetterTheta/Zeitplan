module View exposing (View, container, content, footer, map, none, placeholder, toBrowserDocument, tooltip, zeitplanNav)

import Browser
import FontAwesome as Icon
import FontAwesome.Brands exposing (facebook, github)
import FontAwesome.Solid exposing (heart, music)
import Gen.Route as Route
import Html exposing (Attribute, Html, a, div, h2, img, nav, p, section, span, text)
import Html.Attributes exposing (alt, attribute, class, classList, height, href, src, style, target, width)
import Html.Events exposing (onClick)
import Shared
import Url.Builder as Url


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
    img [ width 28, height 28, alt "Zeitplan logo", src source ] []


container : List (Attribute msg) -> List (Html msg) -> Html msg
container attrs children =
    div (class "container" :: attrs) children


content : List (Attribute msg) -> List (Html msg) -> Html msg
content attrs children =
    div (class "content" :: attrs) children


tooltip : String -> Attribute msg
tooltip message =
    attribute "data-tooltip" message


footer : Html msg
footer =
    Html.footer [ class "footer hero is-dark" ]
        [ content [ class "mt-3 is-flex is-flex-direction-column has-text-weight-bold" ]
            [ p [] [ text "This project was made possible thanks to Professor Victor Drescher at Southeastern Louisiana University." ]
            , div [ class "columns" ]
                [ div [ class "column is-4 is-flex is-flex-direction-column" ]
                    [ h2 [ class "is-5 title" ]
                        [ text "If you found Zeitplan useful" ]
                    , a
                        [ href <| Url.crossOrigin "https://github.com" [ "sponsors", "TheLetterTheta" ] []
                        , target "_blank"
                        ]
                        [ span [ class "icon" ]
                            [ Icon.view heart
                            ]
                        , span [] [ text "Sponsor the project" ]
                        ]
                    , a
                        [ href <| Url.crossOrigin "https://github.com" [ "TheLetterTheta", "Zeitplan" ] []
                        , target "_blank"
                        ]
                        [ span [ class "icon" ]
                            [ Icon.view github
                            ]
                        , span [] [ text "Suggest an edit" ]
                        ]
                    ]
                , div [ class "column is-narrow p-0 divider is-vertical" ] [ text "Also" ]
                , div [ class "column is-4 is-flex is-flex-direction-column" ]
                    [ h2 [ class "is-5 subtitle" ] [ text "Support Mr. Drescher by checking out" ]
                    , a
                        [ href <| Url.crossOrigin "https://www.facebook.com" [ "DrescherMusic" ] []
                        , target "_blank"
                        ]
                        [ span [ class "icon" ]
                            [ Icon.view facebook
                            ]
                        , span [] [ text "Facebook" ]
                        ]
                    , a
                        [ href <| Url.crossOrigin "https://dreschermusic.com" [] []
                        , target "_blank"
                        ]
                        [ span [ class "icon" ]
                            [ Icon.view music
                            ]
                        , span [] [ text "DrescherMusic.com" ]
                        ]
                    ]
                ]
            ]
        ]


isNothing : Maybe s -> Bool
isNothing s =
    case s of
        Just _ ->
            False

        Nothing ->
            True


zeitplanNav :
    { logo : String
    , shared : Shared.Model
    }
    -> Html Shared.Msg
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
                , onClick Shared.ToggleNavbarHamburger
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
                ([ a
                    [ class "navbar-item", href (Route.toHref Route.Home_) ]
                    [ text "Home" ]
                 , a
                    [ class "navbar-item", href (Route.toHref Route.About) ]
                    [ text "About" ]
                 , a
                    [ class "navbar-item", href (Route.toHref Route.Pricing) ]
                    [ text "Pricing" ]
                 ]
                    ++ (if isNothing settings.shared.user then
                            []

                        else
                            [ a
                                [ class "navbar-item"
                                , href (Route.toHref Route.Schedule)
                                ]
                                [ text "Schedule" ]
                            ]
                       )
                )
            , div [ class "navbar-end" ]
                [ if isNothing settings.shared.user then
                    a
                        [ class "navbar-item"
                        , href (Route.toHref Route.Login)
                        ]
                        [ text "Log In"
                        ]

                  else
                    a
                        [ class "navbar-item"
                        , href "#"
                        , onClick Shared.Logout
                        , role "button"
                        ]
                        [ text "Logout"
                        ]
                ]
            ]
        ]


type alias View msg =
    { title : String
    , body : List (Html msg)
    }


none : View msg
none =
    { title = "Zeitplan"
    , body = []
    }


placeholder : String -> View msg
placeholder str =
    { title = str
    , body = [ Html.text str ]
    }


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
