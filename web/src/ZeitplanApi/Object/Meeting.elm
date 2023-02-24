-- Do not manually edit this file, it was auto-generated by dillonkearns/elm-graphql
-- https://github.com/dillonkearns/elm-graphql


module ZeitplanApi.Object.Meeting exposing (..)

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


participants : SelectionSet (List String) ZeitplanApi.Object.Meeting
participants =
    Object.selectionForField "(List String)" "participants" [] (Decode.string |> Decode.list)


title : SelectionSet String ZeitplanApi.Object.Meeting
title =
    Object.selectionForField "String" "title" [] Decode.string


duration : SelectionSet Int ZeitplanApi.Object.Meeting
duration =
    Object.selectionForField "Int" "duration" [] Decode.int


created : SelectionSet ZeitplanApi.ScalarCodecs.Long ZeitplanApi.Object.Meeting
created =
    Object.selectionForField "ScalarCodecs.Long" "created" [] (ZeitplanApi.ScalarCodecs.codecs |> ZeitplanApi.Scalar.unwrapCodecs |> .codecLong |> .decoder)