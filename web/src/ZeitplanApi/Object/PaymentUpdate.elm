-- Do not manually edit this file, it was auto-generated by dillonkearns/elm-graphql
-- https://github.com/dillonkearns/elm-graphql


module ZeitplanApi.Object.PaymentUpdate exposing (..)

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


amount : SelectionSet Int ZeitplanApi.Object.PaymentUpdate
amount =
    Object.selectionForField "Int" "amount" [] Decode.int
