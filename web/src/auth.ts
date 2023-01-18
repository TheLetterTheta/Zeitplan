import { CognitoUser, CognitoUserPool, AuthenticationDetails, CookieStorage, CognitoRefreshToken
    , CognitoIdToken, CognitoAccessToken, CognitoUserSession, ISignUpResult } from 'amazon-cognito-identity-js';

const storage = new CookieStorage({ domain: 'localhost', secure: true, path: '/', expires: 365, sameSite: 'strict' });

const poolData = {
    UserPoolId: 'us-east-1_GiYnFSUmL',
    ClientId: '7o95685e43ki0h7kud5nkp0j0r',
    Storage: storage,
}

const pool = new CognitoUserPool(poolData);

/*
Auth.configure({
    region: 'us-east-1',
    poolId: '',
    poolWebClientId: '',
    signUpVerificationMethod: 'code',
    cookieStorage: {
        domain: 'localhost',
        expires: 7,
        sameSite: 'strict',
        secure: true
    },
})
*/

export interface LoginParameters {
    username: string;
    password: string;
}

export interface SignUpParameters extends LoginParameters {
    autoSignIn?: boolean;
}

export interface LoginResult {
    user: CognitoUser;
    userSub: string;
    userConfirmed: boolean;
}

function getUser(username) {
    return new CognitoUser({ Username: username, Pool: pool, Storage: storage });
}

export function signUp( {username, password} : SignUpParameters ): Promise<ISignUpResult> {
    return new Promise((resolve, reject) => {
        pool.signUp(username, password, [], [], function( err, result ) {
            if ( err || !result ) {
                return reject(err);
            } else {
                console.log(result);
                return resolve(result);
            }
        });
    });
}

export function signIn( { username, password } : LoginParameters ) : Promise<CurrentLoginSession> {
    const cognitoUser = getUser(username);
    
    return new Promise((resolve, reject) => {
        const authProps = new AuthenticationDetails( { Password : password, Username: username } );
        cognitoUser.authenticateUser(authProps, {
            onSuccess: function(_) {
                return getCurrentUser()
                        .then((result) => resolve(result))
                        .catch((err) => reject(err))
            },
            onFailure: function(err) {
                return reject(err);
            },
            mfaRequired: function(codeDeliveryDetails) {
                return reject({ code: 'MFARequired', data: codeDeliveryDetails });
            },
            mfaSetup: function(challengeName, challengeParams) {
                return reject({ code: 'SelectMFAMethod', data: JSON.parse(challengeParams.MFAS_CAN_SETUP) });
            },
            newPasswordRequired: function(_) {
                return reject({ code: 'NewPasswordRequired', data: null });
            }
        })
    });
}

export function signOut(): Promise<void> {
    const cognitoUser = pool.getCurrentUser();

    return new Promise((resolve, reject) => {
        if (cognitoUser === null) {
            return reject("No user logged in");
        } else {
            try {
                cognitoUser.signOut(() => {
                    return resolve();
                });
            } catch (e) {
                reject(e);
            }

        }
    })
}

export function submitMFA(username: string, code: string) : Promise<CognitoUserSession> {
    const cognitoUser = getUser(username);

    return new Promise((resolve, reject) => {
        cognitoUser.sendMFACode(code, {
            onSuccess: function(result) {
                return resolve(result);
            },
            onFailure: function(err) {
                return reject(err);
            }
        });
    });
}

export function submitConfirmationCode(username: string, code: string): Promise<string> {
    const cognitoUser = getUser(username);

    return new Promise((resolve, reject) => {
        cognitoUser.confirmRegistration(code, true, function(err, result) {
            if (err) {
                return reject(err);
            } else {
                // should be 'SUCCESS'
                return resolve(result);
            }
        });
    });
}

export function submitResendConfirmationCode(username: string) : Promise<void> {
    const cognitoUser = getUser(username);

    return new Promise((resolve, reject) => {
        cognitoUser.resendConfirmationCode(function (err, result) {
            if (err) {
                return reject(err);
            } else {
                return resolve(result);
            }
        });
    });
}

export interface CurrentLoginSession {
    validSession: boolean;
    user: CognitoUser;
}

export function getCurrentUser() : Promise<CurrentLoginSession> {
    return new Promise((resolve, reject) => {
        const cognitoUser = pool.getCurrentUser();

        if (cognitoUser !== null) {
            cognitoUser.getSession(function(err, session) {
                if(err) {
                    return reject(err);
                } else {
                    return resolve({ user: cognitoUser, validSession: session.isValid() });
                }
            });
        } else {
            return reject("NoCurrentUser");
        }
    });
}
