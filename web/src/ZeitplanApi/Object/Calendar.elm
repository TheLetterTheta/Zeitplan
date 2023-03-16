-- Do not manually edit this file, it was auto-generated by dillonkearns/elm-graphql
-- https://github.com/dillonkearns/elm-graphql


module ZeitplanApi.Object.Calendar exposing (..)

import Graphql.Internal.Builder.Argument as Argument exposing (Argument)
import Graphql.Internal.Builder.Object as Object
import Graphql.Internal.Encode as Encode exposing (Value)
import Graphql.Operation exposing (RootMutation, RootQuery, RootSubscription)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Decode as Decode
import ZeitplanApi.InputObject
import ZeitplanApi.Interface
import ZeitplanApi.Object
import ZeitplanApi.Scalar
import ZeitplanApi.ScalarCodecs
import ZeitplanApi.Union


name : SelectionSet String ZeitplanApi.Object.Calendar
name =
    Object.selectionForField "String" "name" [] Decode.string


events :
    SelectionSet decodesTo ZeitplanApi.Object.Event
    -> SelectionSet (List decodesTo) ZeitplanApi.Object.Calendar
events object____ =
    Object.selectionForCompositeField "events" [] object____ (Basics.identity >> Decode.list)


blockedDays : SelectionSet (List String) ZeitplanApi.Object.Calendar
blockedDays =
    Object.selectionForField "(List String)" "blockedDays" [] (Decode.string |> Decode.list)
