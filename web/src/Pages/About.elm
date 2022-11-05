module Pages.About exposing (Model, Msg, page)

import Effect exposing (Effect)
import Gen.Params.Home_ exposing (Params)
import Html exposing (a, blockquote, code, div, h1, h2, h5, i, p, strong, text)
import Html.Attributes exposing (class, href, id, style)
import Html.Events exposing (onClick)
import Page
import Request
import Shared
import Url.Builder exposing (Root(..), custom)
import View exposing (View, container, content, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    {}


init : ( Model, Effect Msg )
init =
    ( {}, Effect.none )



-- UPDATE


type Msg
    = SharedMsg Shared.Msg


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared _ =
    { title = "Zeitplan - About"
    , body =
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map
                (\navMsg ->
                    case navMsg of
                        View.ToggleHamburger ->
                            SharedMsg Shared.ToggleNavbarHamburger

                        View.Logout ->
                            SharedMsg Shared.ToggleNavbarHamburger
                )
        , div [ class "is-small section" ]
            [ div [ class "hero is-info" ]
                [ div [ class "hero-body" ]
                    [ h1 [ class "is-1 title" ] [ text "About Zeitplan" ]
                    , h2 [ class "subtitle" ] [ text "A place for questions and (hopefully) answers" ]
                    ]
                ]
            ]
        , div [ class "section" ]
            [ container []
                [ content []
                    [ a
                        [ onClick (SharedMsg <| Shared.ScrollToElement "whats-a-zeitplan")
                        , href <| custom Relative [] [] (Just "whats-a-zeitplan")
                        ]
                        [ h5 [ id "whats-a-zeitplan", class "is-size-3" ] [ text "What's a \"Zeitplan\"? " ]
                        ]
                    , p []
                        [ text """
                        Before we answer that question, we need a little backstory...
                        Victor Drescher is a music professor at Southeastern Louisiana University.
                        The main developer of this application was one of his students, and was working on a piece
                        of music that was German. Mr. Drescher proposed that it took him hours to plan out when to
                        meet with his students on a weekly basis. Thus, the idea of "The Scheduler" was born!
                        """
                        ]
                    , p []
                        [ text """
                        The name, "The Scheduler" wasn't going to stick for very long. So, the project was renamed
                        to the German word for "schedule" instead: Zeitplan! The name was originally meant as a placeholder
                        for a more permanent name, but it eventually stuck. And so, the project is named Zeitplan to this day!
                        """
                        ]
                    , a
                        [ onClick (SharedMsg <| Shared.ScrollToElement "what-does-it-do")
                        , href <| custom Relative [] [] (Just "what-does-it-do")
                        ]
                        [ h5 [ id "what-does-it-do", class "is-size-3" ] [ text "What does it do?" ] ]
                    , p []
                        [ text "Mr. Drescher's original dilema was this:"
                        ]
                    , p [ class "has-text-centered" ]
                        [ i []
                            [ text """
                        There are many apps that help you schedule a single meeting, but nothing that helps me schedule
                        ~20+ meetings at the same time.
                        """
                            ]
                        ]
                    , p []
                        [ text """
                    At first, it sounded unbelieveable. Surely there was something that could simply do the same thing 20x over,
                    and still generate a schedule that fit? Right?
                    """ ]
                    , p []
                        [ text """
                    Wrong! Or if it exists, it's not well known enough to be doing people like Mr. Drescher any good.
                    Nothing that even does 5 meetings at the same time. No matter, it sounds easy enough!
                    """
                        ]
                    , p [ class "has-text-centered" ]
                        [ i []
                            [ text """
                            Just find when each meeting can be scheduled and... oh... this isn't as easy as I thought. 
                            """
                            ]
                        ]
                    , p []
                        [ text """
                        So the problem isn't as easy as originally thought. Turns out what we need is something like a 
                        """
                        , code [ class "is-family-code" ] [ text "cartesian product" ]
                        , text " of all the meetings, and a lot of time looking for the "
                        , strong [] [ text "right combination" ]
                        , text " of those meetings that is a good schedule."
                        ]
                    , p []
                        [ text """
                        And this is the process that many in Mr. Drescher's situation attempting to do by hand. That's where
                        Zeitplan comes in.
                        """
                        ]
                    , blockquote []
                        [ i [] [ text """
                        What used to take me hours to sort student schedules now takes about 45 minutes- it’s fantastic.
                        """ ]
                        , p [] [ text "- Victor Drescher" ]
                        ]
                    , a
                        [ onClick (SharedMsg <| Shared.ScrollToElement "faq")
                        , href <| custom Relative [] [] (Just "faq")
                        ]
                        [ h5 [ id "faq", class "is-size-3" ] [ text "Frequently Asked Questions" ] ]
                    , p []
                        [ strong [] [ text "How many meetings can I schedule?" ] ]
                    , p []
                        [ text """
                    Currently, only a 1 week timeframe can be scheduled. The minimum size of a meeting is 30 min.
                    There are (as everyone is already aware) 336 30-minute intervals in a week. So, the most meetings
                    you could schedule at one time is 336.
                    You can, however generate a schedule this way, and continue to use the program!
                    """ ]
                    , p []
                        [ strong [] [ text "This is taking a long time. I think it's stuck" ] ]
                    , p [ class "is-wrap-text" ]
                        [ text """
                    That's not a question, but I'll answer it anyway! The number of possible schedules we need to analyze for the default
                    week view in Zeitplan is a whopping
                    """
                        , code [ style "word-break" "break-all" ]
                            [ text "707,941,224,973,776,291,093,837,493,051,267,117,605,376,723,076,915,563,513,477,597,978,647,196,852,710,146,048,782,874,897,075,955,894,104,953,184,864,576,196,144,825,576,943,931,128,199,472,378,261,795,861,931,974,957,688,311,237,681,682,031,691,366,087,383,492,525,475,626,202,835,152,044,870,005,449,098,250,592,421,885,320,204,847,428,102,564,080,042,137,500,502,947,619,347,768,122,327,941,080,451,839,131,251,991,696,797,801,434,243,553,028,397,371,613,542,311,928,832,902,663,472,677,761,721,549,526,113,056,029,984,995,819,524,704,354,822,624,666,292,991,477,232,130,327,433,304,881,523,787,028,883,795,947,102,784,291,416,129,589,695,015,805,337,539,264,492,307,555,753,716,879,695,344,357,979,188,084,112,721,486,214,822,552,206,966,345,890,231,289,687,237,950,447,464,115,396,984,096,898,391,196,909,695,809,036,630,324,500,769,619,930,968,248,631,451,227,869,005,449,623,566,329,692,609,930,440,559,431,377,271,635,608,873,359,171,946,166,367,460,584,277,699,826,134,971,929,228,806,950,423,081,181,843,641,763,509,694,660,317,093,440,761,351,296,251,922,615,893,476,691,290,071,647,755,667,379,012,463,240,136,359,936"
                            ]
                        , text """
                    possible configurations. Luckily, a lot of work has been done to optimize what Zeitplan is doing, so that each check
                    is as efficient as possible.
                    """
                        ]
                    ]
                ]
            ]
        , footer
        ]
    }
