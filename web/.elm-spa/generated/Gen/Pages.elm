module Gen.Pages exposing (Model, Msg, init, subscriptions, update, view)

import Browser.Navigation exposing (Key)
import Effect exposing (Effect)
import ElmSpa.Page
import Gen.Params.About
import Gen.Params.Home_
import Gen.Params.Login
import Gen.Params.PaymentConfirmation
import Gen.Params.Pricing
import Gen.Params.Schedule
import Gen.Params.NotFound
import Gen.Model as Model
import Gen.Msg as Msg
import Gen.Route as Route exposing (Route)
import Page exposing (Page)
import Pages.About
import Pages.Home_
import Pages.Login
import Pages.PaymentConfirmation
import Pages.Pricing
import Pages.Schedule
import Pages.NotFound
import Request exposing (Request)
import Shared
import Task
import Url exposing (Url)
import View exposing (View)


type alias Model =
    Model.Model


type alias Msg =
    Msg.Msg


init : Route -> Shared.Model -> Url -> Key -> ( Model, Effect Msg )
init route =
    case route of
        Route.About ->
            pages.about.init ()
    
        Route.Home_ ->
            pages.home_.init ()
    
        Route.Login ->
            pages.login.init ()
    
        Route.PaymentConfirmation ->
            pages.paymentConfirmation.init ()
    
        Route.Pricing ->
            pages.pricing.init ()
    
        Route.Schedule ->
            pages.schedule.init ()
    
        Route.NotFound ->
            pages.notFound.init ()


update : Msg -> Model -> Shared.Model -> Url -> Key -> ( Model, Effect Msg )
update msg_ model_ =
    case ( msg_, model_ ) of
        ( Msg.About msg, Model.About params model ) ->
            pages.about.update params msg model
    
        ( Msg.Home_ msg, Model.Home_ params model ) ->
            pages.home_.update params msg model
    
        ( Msg.Login msg, Model.Login params model ) ->
            pages.login.update params msg model
    
        ( Msg.PaymentConfirmation msg, Model.PaymentConfirmation params model ) ->
            pages.paymentConfirmation.update params msg model
    
        ( Msg.Pricing msg, Model.Pricing params model ) ->
            pages.pricing.update params msg model
    
        ( Msg.Schedule msg, Model.Schedule params model ) ->
            pages.schedule.update params msg model

        _ ->
            \_ _ _ -> ( model_, Effect.none )


view : Model -> Shared.Model -> Url -> Key -> View Msg
view model_ =
    case model_ of
        Model.Redirecting_ ->
            \_ _ _ -> View.none
    
        Model.About params model ->
            pages.about.view params model
    
        Model.Home_ params model ->
            pages.home_.view params model
    
        Model.Login params model ->
            pages.login.view params model
    
        Model.PaymentConfirmation params model ->
            pages.paymentConfirmation.view params model
    
        Model.Pricing params model ->
            pages.pricing.view params model
    
        Model.Schedule params model ->
            pages.schedule.view params model
    
        Model.NotFound params ->
            pages.notFound.view params ()


subscriptions : Model -> Shared.Model -> Url -> Key -> Sub Msg
subscriptions model_ =
    case model_ of
        Model.Redirecting_ ->
            \_ _ _ -> Sub.none
    
        Model.About params model ->
            pages.about.subscriptions params model
    
        Model.Home_ params model ->
            pages.home_.subscriptions params model
    
        Model.Login params model ->
            pages.login.subscriptions params model
    
        Model.PaymentConfirmation params model ->
            pages.paymentConfirmation.subscriptions params model
    
        Model.Pricing params model ->
            pages.pricing.subscriptions params model
    
        Model.Schedule params model ->
            pages.schedule.subscriptions params model
    
        Model.NotFound params ->
            pages.notFound.subscriptions params ()



-- INTERNALS


pages :
    { about : Bundle Gen.Params.About.Params Pages.About.Model Pages.About.Msg
    , home_ : Bundle Gen.Params.Home_.Params Pages.Home_.Model Pages.Home_.Msg
    , login : Bundle Gen.Params.Login.Params Pages.Login.Model Pages.Login.Msg
    , paymentConfirmation : Bundle Gen.Params.PaymentConfirmation.Params Pages.PaymentConfirmation.Model Pages.PaymentConfirmation.Msg
    , pricing : Bundle Gen.Params.Pricing.Params Pages.Pricing.Model Pages.Pricing.Msg
    , schedule : Bundle Gen.Params.Schedule.Params Pages.Schedule.Model Pages.Schedule.Msg
    , notFound : Static Gen.Params.NotFound.Params
    }
pages =
    { about = bundle Pages.About.page Model.About Msg.About
    , home_ = bundle Pages.Home_.page Model.Home_ Msg.Home_
    , login = bundle Pages.Login.page Model.Login Msg.Login
    , paymentConfirmation = bundle Pages.PaymentConfirmation.page Model.PaymentConfirmation Msg.PaymentConfirmation
    , pricing = bundle Pages.Pricing.page Model.Pricing Msg.Pricing
    , schedule = bundle Pages.Schedule.page Model.Schedule Msg.Schedule
    , notFound = static Pages.NotFound.view Model.NotFound
    }


type alias Bundle params model msg =
    ElmSpa.Page.Bundle params model msg Shared.Model (Effect Msg) Model Msg (View Msg)


bundle page toModel toMsg =
    ElmSpa.Page.bundle
        { redirecting =
            { model = Model.Redirecting_
            , view = View.none
            }
        , toRoute = Route.fromUrl
        , toUrl = Route.toHref
        , fromCmd = Effect.fromCmd
        , mapEffect = Effect.map toMsg
        , mapView = View.map toMsg
        , toModel = toModel
        , toMsg = toMsg
        , page = page
        }


type alias Static params =
    Bundle params () Never


static : View Never -> (params -> Model) -> Static params
static view_ toModel =
    { init = \params _ _ _ -> ( toModel params, Effect.none )
    , update = \params _ _ _ _ _ -> ( toModel params, Effect.none )
    , view = \_ _ _ _ _ -> View.map never view_
    , subscriptions = \_ _ _ _ _ -> Sub.none
    }
    
