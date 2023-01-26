module Decoders exposing (AuthUser, SignUpResult, authUserDecoder, signUpResultDecoder)

import Json.Decode as Decode
import Json.Decode.Pipeline exposing (optional, optionalAt, required, requiredAt)
import Json.Encode as Encode



-- Required packages:
-- * elm/json
-- * NoRedInk/elm-json-decode-pipeline


type alias AuthUser =
    { userId : String
    , email : Maybe String
    , jwtToken : String
    }


authUserDecoder : Decode.Decoder AuthUser
authUserDecoder =
    Decode.succeed AuthUser
        |> required "username" Decode.string
        |> optionalAt [ "attributes", "email" ] (Decode.nullable Decode.string) Nothing
        |> requiredAt [ "signInUserSession", "idToken", "jwtToken" ] Decode.string


type alias SignUpResult =
    { userId : String
    , email : Maybe String
    , userConfirmed : Bool
    }


signUpResultDecoder : Decode.Decoder SignUpResult
signUpResultDecoder =
    Decode.succeed SignUpResult
        |> required "userSub" Decode.string
        |> optionalAt ["user", "username"] (Decode.nullable Decode.string) Nothing
        |> required "userConfirmed" Decode.bool
