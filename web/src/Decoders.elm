module Decoders exposing (AuthUser, SignUpResult, authUserDecoder, signUpResultDecoder)

import Json.Decode as Decode
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode



-- Required packages:
-- * elm/json
-- * NoRedInk/elm-json-decode-pipeline


type alias AuthUser =
    { user : AuthUserUser
    , validSession : Bool
    }


type alias AuthUserUser =
    { authenticationFlowType : String
    , client : AuthUserUserClient
    , keyPrefix : String
    , pool : AuthUserUserPool
    , session : ()
    , signInUserSession : AuthUserUserSignInUserSession
    , storage : AuthUserUserStorage
    , userDataKey : String
    , username : String
    }


type alias AuthUserUserClient =
    { endpoint : String
    , fetchOptions : AuthUserUserClientFetchOptions
    }


type alias AuthUserUserClientFetchOptions =
    {}


type alias AuthUserUserPool =
    { advancedSecurityDataCollectionFlag : Bool
    , client : AuthUserUserPoolClient
    , clientId : String
    , storage : AuthUserUserPoolStorage
    , userPoolId : String
    }


type alias AuthUserUserPoolClient =
    { endpoint : String
    , fetchOptions : AuthUserUserPoolClientFetchOptions
    }


type alias AuthUserUserPoolClientFetchOptions =
    {}


type alias AuthUserUserPoolStorage =
    { domain : String
    , expires : Int
    , path : String
    , sameSite : String
    , secure : Bool
    }


type alias AuthUserUserSignInUserSession =
    { accessToken : AuthUserUserSignInUserSessionAccessToken
    , clockDrift : Int
    , idToken : AuthUserUserSignInUserSessionIdToken
    , refreshToken : AuthUserUserSignInUserSessionRefreshToken
    }


type alias AuthUserUserSignInUserSessionAccessToken =
    { jwtToken : String
    , payload : AuthUserUserSignInUserSessionAccessTokenPayload
    }


type alias AuthUserUserSignInUserSessionAccessTokenPayload =
    { authTime : Int
    , clientId : String
    , eventId : String
    , exp : Int
    , iat : Int
    , iss : String
    , jti : String
    , originJti : String
    , scope : String
    , sub : String
    , tokenUse : String
    , username : String
    }


type alias AuthUserUserSignInUserSessionIdToken =
    { jwtToken : String
    , payload : AuthUserUserSignInUserSessionIdTokenPayload
    }


type alias AuthUserUserSignInUserSessionIdTokenPayload =
    { aud : String
    , authTime : Int
    , cognitoU58username : String
    , email : String
    , emailVerified : Bool
    , eventId : String
    , exp : Int
    , iat : Int
    , iss : String
    , jti : String
    , originJti : String
    , sub : String
    , tokenUse : String
    }


type alias AuthUserUserSignInUserSessionRefreshToken =
    { token : String
    }


type alias AuthUserUserStorage =
    { domain : String
    , expires : Int
    , path : String
    , sameSite : String
    , secure : Bool
    }


authUserDecoder : Decode.Decoder AuthUser
authUserDecoder =
    Decode.succeed AuthUser
        |> required "user" authUserUserDecoder
        |> required "validSession" Decode.bool


authUserUserDecoder : Decode.Decoder AuthUserUser
authUserUserDecoder =
    Decode.succeed AuthUserUser
        |> required "authenticationFlowType" Decode.string
        |> required "client" authUserUserClientDecoder
        |> required "keyPrefix" Decode.string
        |> required "pool" authUserUserPoolDecoder
        |> required "Session" (Decode.null ())
        |> required "signInUserSession" authUserUserSignInUserSessionDecoder
        |> required "storage" authUserUserStorageDecoder
        |> required "userDataKey" Decode.string
        |> required "username" Decode.string


authUserUserClientDecoder : Decode.Decoder AuthUserUserClient
authUserUserClientDecoder =
    Decode.succeed AuthUserUserClient
        |> required "endpoint" Decode.string
        |> required "fetchOptions" authUserUserClientFetchOptionsDecoder


authUserUserClientFetchOptionsDecoder : Decode.Decoder AuthUserUserClientFetchOptions
authUserUserClientFetchOptionsDecoder =
    Decode.succeed AuthUserUserClientFetchOptions


authUserUserPoolDecoder : Decode.Decoder AuthUserUserPool
authUserUserPoolDecoder =
    Decode.succeed AuthUserUserPool
        |> required "advancedSecurityDataCollectionFlag" Decode.bool
        |> required "client" authUserUserPoolClientDecoder
        |> required "clientId" Decode.string
        |> required "storage" authUserUserPoolStorageDecoder
        |> required "userPoolId" Decode.string


authUserUserPoolClientDecoder : Decode.Decoder AuthUserUserPoolClient
authUserUserPoolClientDecoder =
    Decode.succeed AuthUserUserPoolClient
        |> required "endpoint" Decode.string
        |> required "fetchOptions" authUserUserPoolClientFetchOptionsDecoder


authUserUserPoolClientFetchOptionsDecoder : Decode.Decoder AuthUserUserPoolClientFetchOptions
authUserUserPoolClientFetchOptionsDecoder =
    Decode.succeed AuthUserUserPoolClientFetchOptions


authUserUserPoolStorageDecoder : Decode.Decoder AuthUserUserPoolStorage
authUserUserPoolStorageDecoder =
    Decode.succeed AuthUserUserPoolStorage
        |> required "domain" Decode.string
        |> required "expires" Decode.int
        |> required "path" Decode.string
        |> required "sameSite" Decode.string
        |> required "secure" Decode.bool


authUserUserSignInUserSessionDecoder : Decode.Decoder AuthUserUserSignInUserSession
authUserUserSignInUserSessionDecoder =
    Decode.succeed AuthUserUserSignInUserSession
        |> required "accessToken" authUserUserSignInUserSessionAccessTokenDecoder
        |> required "clockDrift" Decode.int
        |> required "idToken" authUserUserSignInUserSessionIdTokenDecoder
        |> required "refreshToken" authUserUserSignInUserSessionRefreshTokenDecoder


authUserUserSignInUserSessionAccessTokenDecoder : Decode.Decoder AuthUserUserSignInUserSessionAccessToken
authUserUserSignInUserSessionAccessTokenDecoder =
    Decode.succeed AuthUserUserSignInUserSessionAccessToken
        |> required "jwtToken" Decode.string
        |> required "payload" authUserUserSignInUserSessionAccessTokenPayloadDecoder


authUserUserSignInUserSessionAccessTokenPayloadDecoder : Decode.Decoder AuthUserUserSignInUserSessionAccessTokenPayload
authUserUserSignInUserSessionAccessTokenPayloadDecoder =
    Decode.succeed AuthUserUserSignInUserSessionAccessTokenPayload
        |> required "auth_time" Decode.int
        |> required "client_id" Decode.string
        |> required "event_id" Decode.string
        |> required "exp" Decode.int
        |> required "iat" Decode.int
        |> required "iss" Decode.string
        |> required "jti" Decode.string
        |> required "origin_jti" Decode.string
        |> required "scope" Decode.string
        |> required "sub" Decode.string
        |> required "token_use" Decode.string
        |> required "username" Decode.string


authUserUserSignInUserSessionIdTokenDecoder : Decode.Decoder AuthUserUserSignInUserSessionIdToken
authUserUserSignInUserSessionIdTokenDecoder =
    Decode.succeed AuthUserUserSignInUserSessionIdToken
        |> required "jwtToken" Decode.string
        |> required "payload" authUserUserSignInUserSessionIdTokenPayloadDecoder


authUserUserSignInUserSessionIdTokenPayloadDecoder : Decode.Decoder AuthUserUserSignInUserSessionIdTokenPayload
authUserUserSignInUserSessionIdTokenPayloadDecoder =
    Decode.succeed AuthUserUserSignInUserSessionIdTokenPayload
        |> required "aud" Decode.string
        |> required "auth_time" Decode.int
        |> required "cognito:username" Decode.string
        |> required "email" Decode.string
        |> required "email_verified" Decode.bool
        |> required "event_id" Decode.string
        |> required "exp" Decode.int
        |> required "iat" Decode.int
        |> required "iss" Decode.string
        |> required "jti" Decode.string
        |> required "origin_jti" Decode.string
        |> required "sub" Decode.string
        |> required "token_use" Decode.string


authUserUserSignInUserSessionRefreshTokenDecoder : Decode.Decoder AuthUserUserSignInUserSessionRefreshToken
authUserUserSignInUserSessionRefreshTokenDecoder =
    Decode.succeed AuthUserUserSignInUserSessionRefreshToken
        |> required "token" Decode.string


authUserUserStorageDecoder : Decode.Decoder AuthUserUserStorage
authUserUserStorageDecoder =
    Decode.succeed AuthUserUserStorage
        |> required "domain" Decode.string
        |> required "expires" Decode.int
        |> required "path" Decode.string
        |> required "sameSite" Decode.string
        |> required "secure" Decode.bool


encodedAuthUser : AuthUser -> Encode.Value
encodedAuthUser authUser =
    Encode.object
        [ ( "user", encodedAuthUserUser authUser.user )
        , ( "validSession", Encode.bool authUser.validSession )
        ]


encodedAuthUserUser : AuthUserUser -> Encode.Value
encodedAuthUserUser authUserUser =
    Encode.object
        [ ( "authenticationFlowType", Encode.string authUserUser.authenticationFlowType )
        , ( "client", encodedAuthUserUserClient authUserUser.client )
        , ( "keyPrefix", Encode.string authUserUser.keyPrefix )
        , ( "pool", encodedAuthUserUserPool authUserUser.pool )
        , ( "Session", Encode.null )
        , ( "signInUserSession", encodedAuthUserUserSignInUserSession authUserUser.signInUserSession )
        , ( "storage", encodedAuthUserUserStorage authUserUser.storage )
        , ( "userDataKey", Encode.string authUserUser.userDataKey )
        , ( "username", Encode.string authUserUser.username )
        ]


encodedAuthUserUserClient : AuthUserUserClient -> Encode.Value
encodedAuthUserUserClient authUserUserClient =
    Encode.object
        [ ( "endpoint", Encode.string authUserUserClient.endpoint )
        , ( "fetchOptions", encodedAuthUserUserClientFetchOptions authUserUserClient.fetchOptions )
        ]


encodedAuthUserUserClientFetchOptions : AuthUserUserClientFetchOptions -> Encode.Value
encodedAuthUserUserClientFetchOptions authUserUserClientFetchOptions =
    Encode.object
        []


encodedAuthUserUserPool : AuthUserUserPool -> Encode.Value
encodedAuthUserUserPool authUserUserPool =
    Encode.object
        [ ( "advancedSecurityDataCollectionFlag", Encode.bool authUserUserPool.advancedSecurityDataCollectionFlag )
        , ( "client", encodedAuthUserUserPoolClient authUserUserPool.client )
        , ( "clientId", Encode.string authUserUserPool.clientId )
        , ( "storage", encodedAuthUserUserPoolStorage authUserUserPool.storage )
        , ( "userPoolId", Encode.string authUserUserPool.userPoolId )
        ]


encodedAuthUserUserPoolClient : AuthUserUserPoolClient -> Encode.Value
encodedAuthUserUserPoolClient authUserUserPoolClient =
    Encode.object
        [ ( "endpoint", Encode.string authUserUserPoolClient.endpoint )
        , ( "fetchOptions", encodedAuthUserUserPoolClientFetchOptions authUserUserPoolClient.fetchOptions )
        ]


encodedAuthUserUserPoolClientFetchOptions : AuthUserUserPoolClientFetchOptions -> Encode.Value
encodedAuthUserUserPoolClientFetchOptions authUserUserPoolClientFetchOptions =
    Encode.object
        []


encodedAuthUserUserPoolStorage : AuthUserUserPoolStorage -> Encode.Value
encodedAuthUserUserPoolStorage authUserUserPoolStorage =
    Encode.object
        [ ( "domain", Encode.string authUserUserPoolStorage.domain )
        , ( "expires", Encode.int authUserUserPoolStorage.expires )
        , ( "path", Encode.string authUserUserPoolStorage.path )
        , ( "sameSite", Encode.string authUserUserPoolStorage.sameSite )
        , ( "secure", Encode.bool authUserUserPoolStorage.secure )
        ]


encodedAuthUserUserSignInUserSession : AuthUserUserSignInUserSession -> Encode.Value
encodedAuthUserUserSignInUserSession authUserUserSignInUserSession =
    Encode.object
        [ ( "accessToken", encodedAuthUserUserSignInUserSessionAccessToken authUserUserSignInUserSession.accessToken )
        , ( "clockDrift", Encode.int authUserUserSignInUserSession.clockDrift )
        , ( "idToken", encodedAuthUserUserSignInUserSessionIdToken authUserUserSignInUserSession.idToken )
        , ( "refreshToken", encodedAuthUserUserSignInUserSessionRefreshToken authUserUserSignInUserSession.refreshToken )
        ]


encodedAuthUserUserSignInUserSessionAccessToken : AuthUserUserSignInUserSessionAccessToken -> Encode.Value
encodedAuthUserUserSignInUserSessionAccessToken authUserUserSignInUserSessionAccessToken =
    Encode.object
        [ ( "jwtToken", Encode.string authUserUserSignInUserSessionAccessToken.jwtToken )
        , ( "payload", encodedAuthUserUserSignInUserSessionAccessTokenPayload authUserUserSignInUserSessionAccessToken.payload )
        ]


encodedAuthUserUserSignInUserSessionAccessTokenPayload : AuthUserUserSignInUserSessionAccessTokenPayload -> Encode.Value
encodedAuthUserUserSignInUserSessionAccessTokenPayload authUserUserSignInUserSessionAccessTokenPayload =
    Encode.object
        [ ( "auth_time", Encode.int authUserUserSignInUserSessionAccessTokenPayload.authTime )
        , ( "client_id", Encode.string authUserUserSignInUserSessionAccessTokenPayload.clientId )
        , ( "event_id", Encode.string authUserUserSignInUserSessionAccessTokenPayload.eventId )
        , ( "exp", Encode.int authUserUserSignInUserSessionAccessTokenPayload.exp )
        , ( "iat", Encode.int authUserUserSignInUserSessionAccessTokenPayload.iat )
        , ( "iss", Encode.string authUserUserSignInUserSessionAccessTokenPayload.iss )
        , ( "jti", Encode.string authUserUserSignInUserSessionAccessTokenPayload.jti )
        , ( "origin_jti", Encode.string authUserUserSignInUserSessionAccessTokenPayload.originJti )
        , ( "scope", Encode.string authUserUserSignInUserSessionAccessTokenPayload.scope )
        , ( "sub", Encode.string authUserUserSignInUserSessionAccessTokenPayload.sub )
        , ( "token_use", Encode.string authUserUserSignInUserSessionAccessTokenPayload.tokenUse )
        , ( "username", Encode.string authUserUserSignInUserSessionAccessTokenPayload.username )
        ]


encodedAuthUserUserSignInUserSessionIdToken : AuthUserUserSignInUserSessionIdToken -> Encode.Value
encodedAuthUserUserSignInUserSessionIdToken authUserUserSignInUserSessionIdToken =
    Encode.object
        [ ( "jwtToken", Encode.string authUserUserSignInUserSessionIdToken.jwtToken )
        , ( "payload", encodedAuthUserUserSignInUserSessionIdTokenPayload authUserUserSignInUserSessionIdToken.payload )
        ]


encodedAuthUserUserSignInUserSessionIdTokenPayload : AuthUserUserSignInUserSessionIdTokenPayload -> Encode.Value
encodedAuthUserUserSignInUserSessionIdTokenPayload authUserUserSignInUserSessionIdTokenPayload =
    Encode.object
        [ ( "aud", Encode.string authUserUserSignInUserSessionIdTokenPayload.aud )
        , ( "auth_time", Encode.int authUserUserSignInUserSessionIdTokenPayload.authTime )
        , ( "cognito:username", Encode.string authUserUserSignInUserSessionIdTokenPayload.cognitoU58username )
        , ( "email", Encode.string authUserUserSignInUserSessionIdTokenPayload.email )
        , ( "email_verified", Encode.bool authUserUserSignInUserSessionIdTokenPayload.emailVerified )
        , ( "event_id", Encode.string authUserUserSignInUserSessionIdTokenPayload.eventId )
        , ( "exp", Encode.int authUserUserSignInUserSessionIdTokenPayload.exp )
        , ( "iat", Encode.int authUserUserSignInUserSessionIdTokenPayload.iat )
        , ( "iss", Encode.string authUserUserSignInUserSessionIdTokenPayload.iss )
        , ( "jti", Encode.string authUserUserSignInUserSessionIdTokenPayload.jti )
        , ( "origin_jti", Encode.string authUserUserSignInUserSessionIdTokenPayload.originJti )
        , ( "sub", Encode.string authUserUserSignInUserSessionIdTokenPayload.sub )
        , ( "token_use", Encode.string authUserUserSignInUserSessionIdTokenPayload.tokenUse )
        ]


encodedAuthUserUserSignInUserSessionRefreshToken : AuthUserUserSignInUserSessionRefreshToken -> Encode.Value
encodedAuthUserUserSignInUserSessionRefreshToken authUserUserSignInUserSessionRefreshToken =
    Encode.object
        [ ( "token", Encode.string authUserUserSignInUserSessionRefreshToken.token )
        ]


encodedAuthUserUserStorage : AuthUserUserStorage -> Encode.Value
encodedAuthUserUserStorage authUserUserStorage =
    Encode.object
        [ ( "domain", Encode.string authUserUserStorage.domain )
        , ( "expires", Encode.int authUserUserStorage.expires )
        , ( "path", Encode.string authUserUserStorage.path )
        , ( "sameSite", Encode.string authUserUserStorage.sameSite )
        , ( "secure", Encode.bool authUserUserStorage.secure )
        ]


type alias SignUpResult =
    { codeDeliveryDetails : SignUpResultCodeDeliveryDetails
    , user : SignUpResultUser
    , userConfirmed : Bool
    , userSub : String
    }


type alias SignUpResultCodeDeliveryDetails =
    { attributeName : String
    , deliveryMedium : String
    , destination : String
    }


type alias SignUpResultUser =
    { authenticationFlowType : String
    , client : SignUpResultUserClient
    , keyPrefix : String
    , pool : SignUpResultUserPool
    , session : ()
    , signInUserSession : ()
    , storage : SignUpResultUserStorage
    , userDataKey : String
    , username : String
    }


type alias SignUpResultUserClient =
    { endpoint : String
    , fetchOptions : SignUpResultUserClientFetchOptions
    }


type alias SignUpResultUserClientFetchOptions =
    {}


type alias SignUpResultUserPool =
    { advancedSecurityDataCollectionFlag : Bool
    , client : SignUpResultUserPoolClient
    , clientId : String
    , storage : SignUpResultUserPoolStorage
    , userPoolId : String
    }


type alias SignUpResultUserPoolClient =
    { endpoint : String
    , fetchOptions : SignUpResultUserPoolClientFetchOptions
    }


type alias SignUpResultUserPoolClientFetchOptions =
    {}


type alias SignUpResultUserPoolStorage =
    { domain : String
    , expires : Int
    , path : String
    , sameSite : String
    , secure : Bool
    }


type alias SignUpResultUserStorage =
    { domain : String
    , expires : Int
    , path : String
    , sameSite : String
    , secure : Bool
    }


signUpResultDecoder : Decode.Decoder SignUpResult
signUpResultDecoder =
    Decode.succeed SignUpResult
        |> required "codeDeliveryDetails" signUpResultCodeDeliveryDetailsDecoder
        |> required "user" signUpResultUserDecoder
        |> required "userConfirmed" Decode.bool
        |> required "userSub" Decode.string


signUpResultCodeDeliveryDetailsDecoder : Decode.Decoder SignUpResultCodeDeliveryDetails
signUpResultCodeDeliveryDetailsDecoder =
    Decode.succeed SignUpResultCodeDeliveryDetails
        |> required "AttributeName" Decode.string
        |> required "DeliveryMedium" Decode.string
        |> required "Destination" Decode.string


signUpResultUserDecoder : Decode.Decoder SignUpResultUser
signUpResultUserDecoder =
    Decode.succeed SignUpResultUser
        |> required "authenticationFlowType" Decode.string
        |> required "client" signUpResultUserClientDecoder
        |> required "keyPrefix" Decode.string
        |> required "pool" signUpResultUserPoolDecoder
        |> required "Session" (Decode.null ())
        |> required "signInUserSession" (Decode.null ())
        |> required "storage" signUpResultUserStorageDecoder
        |> required "userDataKey" Decode.string
        |> required "username" Decode.string


signUpResultUserClientDecoder : Decode.Decoder SignUpResultUserClient
signUpResultUserClientDecoder =
    Decode.succeed SignUpResultUserClient
        |> required "endpoint" Decode.string
        |> required "fetchOptions" signUpResultUserClientFetchOptionsDecoder


signUpResultUserClientFetchOptionsDecoder : Decode.Decoder SignUpResultUserClientFetchOptions
signUpResultUserClientFetchOptionsDecoder =
    Decode.succeed SignUpResultUserClientFetchOptions


signUpResultUserPoolDecoder : Decode.Decoder SignUpResultUserPool
signUpResultUserPoolDecoder =
    Decode.succeed SignUpResultUserPool
        |> required "advancedSecurityDataCollectionFlag" Decode.bool
        |> required "client" signUpResultUserPoolClientDecoder
        |> required "clientId" Decode.string
        |> required "storage" signUpResultUserPoolStorageDecoder
        |> required "userPoolId" Decode.string


signUpResultUserPoolClientDecoder : Decode.Decoder SignUpResultUserPoolClient
signUpResultUserPoolClientDecoder =
    Decode.succeed SignUpResultUserPoolClient
        |> required "endpoint" Decode.string
        |> required "fetchOptions" signUpResultUserPoolClientFetchOptionsDecoder


signUpResultUserPoolClientFetchOptionsDecoder : Decode.Decoder SignUpResultUserPoolClientFetchOptions
signUpResultUserPoolClientFetchOptionsDecoder =
    Decode.succeed SignUpResultUserPoolClientFetchOptions


signUpResultUserPoolStorageDecoder : Decode.Decoder SignUpResultUserPoolStorage
signUpResultUserPoolStorageDecoder =
    Decode.succeed SignUpResultUserPoolStorage
        |> required "domain" Decode.string
        |> required "expires" Decode.int
        |> required "path" Decode.string
        |> required "sameSite" Decode.string
        |> required "secure" Decode.bool


signUpResultUserStorageDecoder : Decode.Decoder SignUpResultUserStorage
signUpResultUserStorageDecoder =
    Decode.succeed SignUpResultUserStorage
        |> required "domain" Decode.string
        |> required "expires" Decode.int
        |> required "path" Decode.string
        |> required "sameSite" Decode.string
        |> required "secure" Decode.bool


encodedSignUpResult : SignUpResult -> Encode.Value
encodedSignUpResult signUpResult =
    Encode.object
        [ ( "codeDeliveryDetails", encodedSignUpResultCodeDeliveryDetails signUpResult.codeDeliveryDetails )
        , ( "user", encodedSignUpResultUser signUpResult.user )
        , ( "userConfirmed", Encode.bool signUpResult.userConfirmed )
        , ( "userSub", Encode.string signUpResult.userSub )
        ]


encodedSignUpResultCodeDeliveryDetails : SignUpResultCodeDeliveryDetails -> Encode.Value
encodedSignUpResultCodeDeliveryDetails signUpResultCodeDeliveryDetails =
    Encode.object
        [ ( "AttributeName", Encode.string signUpResultCodeDeliveryDetails.attributeName )
        , ( "DeliveryMedium", Encode.string signUpResultCodeDeliveryDetails.deliveryMedium )
        , ( "Destination", Encode.string signUpResultCodeDeliveryDetails.destination )
        ]


encodedSignUpResultUser : SignUpResultUser -> Encode.Value
encodedSignUpResultUser signUpResultUser =
    Encode.object
        [ ( "authenticationFlowType", Encode.string signUpResultUser.authenticationFlowType )
        , ( "client", encodedSignUpResultUserClient signUpResultUser.client )
        , ( "keyPrefix", Encode.string signUpResultUser.keyPrefix )
        , ( "pool", encodedSignUpResultUserPool signUpResultUser.pool )
        , ( "Session", Encode.null )
        , ( "signInUserSession", Encode.null )
        , ( "storage", encodedSignUpResultUserStorage signUpResultUser.storage )
        , ( "userDataKey", Encode.string signUpResultUser.userDataKey )
        , ( "username", Encode.string signUpResultUser.username )
        ]


encodedSignUpResultUserClient : SignUpResultUserClient -> Encode.Value
encodedSignUpResultUserClient signUpResultUserClient =
    Encode.object
        [ ( "endpoint", Encode.string signUpResultUserClient.endpoint )
        , ( "fetchOptions", encodedSignUpResultUserClientFetchOptions signUpResultUserClient.fetchOptions )
        ]


encodedSignUpResultUserClientFetchOptions : SignUpResultUserClientFetchOptions -> Encode.Value
encodedSignUpResultUserClientFetchOptions signUpResultUserClientFetchOptions =
    Encode.object
        []


encodedSignUpResultUserPool : SignUpResultUserPool -> Encode.Value
encodedSignUpResultUserPool signUpResultUserPool =
    Encode.object
        [ ( "advancedSecurityDataCollectionFlag", Encode.bool signUpResultUserPool.advancedSecurityDataCollectionFlag )
        , ( "client", encodedSignUpResultUserPoolClient signUpResultUserPool.client )
        , ( "clientId", Encode.string signUpResultUserPool.clientId )
        , ( "storage", encodedSignUpResultUserPoolStorage signUpResultUserPool.storage )
        , ( "userPoolId", Encode.string signUpResultUserPool.userPoolId )
        ]


encodedSignUpResultUserPoolClient : SignUpResultUserPoolClient -> Encode.Value
encodedSignUpResultUserPoolClient signUpResultUserPoolClient =
    Encode.object
        [ ( "endpoint", Encode.string signUpResultUserPoolClient.endpoint )
        , ( "fetchOptions", encodedSignUpResultUserPoolClientFetchOptions signUpResultUserPoolClient.fetchOptions )
        ]


encodedSignUpResultUserPoolClientFetchOptions : SignUpResultUserPoolClientFetchOptions -> Encode.Value
encodedSignUpResultUserPoolClientFetchOptions signUpResultUserPoolClientFetchOptions =
    Encode.object
        []


encodedSignUpResultUserPoolStorage : SignUpResultUserPoolStorage -> Encode.Value
encodedSignUpResultUserPoolStorage signUpResultUserPoolStorage =
    Encode.object
        [ ( "domain", Encode.string signUpResultUserPoolStorage.domain )
        , ( "expires", Encode.int signUpResultUserPoolStorage.expires )
        , ( "path", Encode.string signUpResultUserPoolStorage.path )
        , ( "sameSite", Encode.string signUpResultUserPoolStorage.sameSite )
        , ( "secure", Encode.bool signUpResultUserPoolStorage.secure )
        ]


encodedSignUpResultUserStorage : SignUpResultUserStorage -> Encode.Value
encodedSignUpResultUserStorage signUpResultUserStorage =
    Encode.object
        [ ( "domain", Encode.string signUpResultUserStorage.domain )
        , ( "expires", Encode.int signUpResultUserStorage.expires )
        , ( "path", Encode.string signUpResultUserStorage.path )
        , ( "sameSite", Encode.string signUpResultUserStorage.sameSite )
        , ( "secure", Encode.bool signUpResultUserStorage.secure )
        ]
