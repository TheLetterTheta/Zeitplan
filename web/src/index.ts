import zeitplanLogo from "../public/Zeitplan.png?as=webp&width:50";
import { CognitoUserPool, CognitoUser } from 'amazon-cognito-identity-js';
import {signIn, signUp, signOut, submitConfirmationCode, submitResendConfirmationCode, getCurrentUser} from './auth';
import { Elm } from "./Main.elm";

function mapError<T>(promise: Promise<T>, map: (error: any) => T): Promise<T> {
    return promise
        .catch(map)
}

function ignoreException<T>(promise: Promise<T>, doFinally: (result: any) => void): Promise<void> {
    return promise
        .then((v) => doFinally({...v, succeeded: true}))
        .catch((v) => doFinally({...v, succeeded: false}))
}

interface LoggedInUser {
    username: string;
    userSub: string;
}

async function run() {
    const currentlyLoggedInUser: LoggedInUser | null = await mapError(getCurrentUser(), () => null);

    console.log(currentlyLoggedInUser);

    const app = Elm.Main.init({
        flags: {
            currentlyLoggedInUser,
            logo: zeitplanLogo
        },
        node: document.getElementById('zeitplan')
    })

    app.ports.saveKey.subscribe(({ key, value }) => {
        localStorage.setItem(key, JSON.stringify(value));
    })
    
   app.ports.signIn.subscribe(signInParams =>
       signIn(signInParams)
        .then(app.ports.signInOk.send)
        .catch(app.ports.signInErr.send)
   );

   app.ports.signUp.subscribe(signUpParams =>
       signUp(signUpParams)
        .then(app.ports.signUpOk.send)
        .catch(app.ports.signUpErr.send)
   );

   app.ports.signUpConfirm.subscribe(( {username, code} ) =>
       submitConfirmationCode(username, code)
        .then(app.ports.signUpConfirmOk.send)
        .catch(app.ports.signUpConfirmErr.send)
   );

   app.ports.resendConfirmationCode.subscribe((username) =>
       submitResendConfirmationCode(username)
           .then(app.ports.resendConfirmationCodeOk.send)
           .catch(app.ports.resendConfirmationCodeErr.send)
   );

   app.ports.signOut.subscribe(username => {
       signOut(username)
           .then(app.ports.signOutOk.send)
           .catch(app.ports.signOutErr.send)
   });


   /*
   app.ports.resendConfirmationCode.subscribe( username => {
       submitResendConfirmationCode(username)
        .then(app.ports.resendConfirmationCodeOk.send)
        .catch(app.ports.resendConfirmationCodeErr.send)
   });
   */

}

run()
