import zeitplanLogo from "../public/favicon_x32.png?as=webp&width:28";
import * as process from "process";
import { Elm } from "./Main.elm";
import {
  loadStripe,
  Stripe,
  StripeElements,
  StripeError,
  StripeLinkAuthenticationElement,
  StripePaymentElement,
  StripePaymentRequestButtonElement,
} from "@stripe/stripe-js";
import { Amplify, Auth } from "aws-amplify";
import { CognitoHostedUIIdentityProvider } from '@aws-amplify/auth';
import { ZeitplanCdkStack } from "../aws-cdk-outputs.json";

Amplify.configure({
  Auth: {
    region: ZeitplanCdkStack.region,
    userPoolId: ZeitplanCdkStack.userpoolid,
    userPoolWebClientId: ZeitplanCdkStack.webclientid,
    signUpVerificationMethod: "code",
    cookieStorage: {
      domain: 'localhost', // .zeitplan-app.com
      path: "/",
      expires: 7,
      sameSite: "strict",
      secure: true,
    },
    authenticationFlowType: "USER_SRP_AUTH",
    oauth: {
      domain: ZeitplanCdkStack.HostedUiDomain.replace("https://", ""),
      redirectSignIn: 'https://localhost:1234/schedule', // https://www.zeitplan-app.com/schedule
      redirectSignOut: 'https://localhost:1234/', // https://www.zeitplan-app.com/
      responseType: 'code'
    }
  },
});


function mapError<T>(promise: Promise<T>, map: (error: any) => T): Promise<T> {
  return promise.catch(map);
}

customElements.define(
  "stripe-web-component",
  class extends HTMLElement {

    private _clientSecret: string | null = null;
    private _stripe: Stripe | null = null;
    private _elements: StripeElements | null = null;
    private _submitButton: HTMLButtonElement;
    private _form: HTMLFormElement;
    private _linkAuthenticationEL: HTMLDivElement;
    private _paymentEL: HTMLDivElement;
    private _paymentButtonEL: HTMLDivElement;
    private _stripeLinkAuthenticationEL: StripeLinkAuthenticationElement;
    private _stripePaymentEL: StripePaymentElement;
    private _stripePaymentRequest: StripePaymentRequestButtonElement;
    private _email: string | null;
    private _error: StripeError;

    constructor() {
      super();
      loadStripe(process.env.STRIPE_PUBLIC_API_KEY).then((stripe) => {
        this._stripe = stripe;
        this.connectedCallback()
      });
    }

    connectedCallback() {
      if (this._stripe === null || !this.hasAttribute("client-secret")) return;

      this._elements = this._stripe.elements({
        clientSecret: this.getAttribute("client-secret"),
        appearance: {
          theme: "flat"
        }
      });

      this._form = document.createElement("form");
      this._paymentEL = document.createElement("div");
      this._linkAuthenticationEL = document.createElement("div");
      this._submitButton = document.createElement("button");
      this._submitButton.type = "submit";
      this._submitButton.classList.add("button");
      this._submitButton.classList.add("is-success");
      this._submitButton.classList.add("mt-2");
      this._submitButton.textContent = "Submit Payment";

      this._form.appendChild(this._linkAuthenticationEL);
      this._form.appendChild(this._paymentEL);
      this._form.appendChild(this._submitButton);

      this.append(this._form);

      this._stripePaymentEL = this._elements.create("payment");
      this._stripeLinkAuthenticationEL =
        this._elements.create("linkAuthentication");

      this._stripeLinkAuthenticationEL.on("change", (event) => {
        this._email = event.value.email;
        this.dispatchEvent(
          new CustomEvent("emailChanged", { detail: event.value.email })
        );
      });

      this._stripePaymentEL.mount(this._paymentEL);
      this._stripeLinkAuthenticationEL.mount(this._linkAuthenticationEL);

      this._form.onsubmit = async (e) => {
        e.preventDefault();
        if (this._elements === null || this._stripe === null) return;

        const { error } = await this._stripe?.confirmPayment({
          elements: this._elements,
          confirmParams: {
            return_url: `${window.location.protocol}//${window.location.hostname
              }${window.location.port ? ":" + window.location.port : ""
              }/payment-confirmation`,
            receipt_email: this._email ?? undefined,
          },
        });

        this._error = error;
        this.dispatchEvent(
          new CustomEvent("paymentError", {
            detail: error,
          })
        );
      };
    }
  }
);

async function run() {
  const currentlyLoggedInUser = await mapError(
    Auth.currentAuthenticatedUser().then(async (user) => {
      return Auth.currentSession()
        .then((token) => token.getAccessToken())
        .then((token) => {
          return {
            ...user,
            jwt: token.getJwtToken(),
            expires: token.getExpiration() * 1000,
          };
        });
    }),
    () => null
  );

  const graphQlEndpoint = ZeitplanCdkStack.graphqlapiendpoint;

  const app = Elm.Main.init({
    flags: {
      currentlyLoggedInUser,
      logo: zeitplanLogo,
      graphQlEndpoint,
    },
    node: document.getElementById("zeitplan"),
  });

  app.ports.signIn.subscribe(({ username, password }) =>
    Auth.signIn(username, password)
      .then(async (user) => {
        return Auth.currentSession()
          .then((token) => token.getAccessToken())
          .then((token) => {
            return {
              ...user,
              jwt: token.getJwtToken(),
              expires: token.getExpiration() * 1000,
            };
          });
      })
      .then(app.ports.signInOk.send)
      .catch(app.ports.signInErr.send)
  );

  app.ports.signUp.subscribe(({ username, password }) => {
    Auth.signUp({
      username,
      password,
      autoSignIn: { enabled: true },
    })
      .then(app.ports.signUpOk.send)
      .catch(app.ports.signUpErr.send);
  });

  app.ports.signUpConfirm.subscribe(({ username, code }) => {
    Auth.confirmSignUp(username, code)
      .then((_) => Auth.currentAuthenticatedUser({ bypassCache: true }))
      .then(async (user) => {
        return Auth.currentSession()
          .then((token) => token.getAccessToken())
          .then((token) => ({
            ...user,
            jwt: token.getJwtToken(),
            expires: token.getExpiration() * 1000,
          }));
      })
      .then(app.ports.signUpConfirmOk.send)
      .catch((e) => {
        if ( e.code === undefined || e.code === null ) {
          window.location.reload();
        }

        app.ports.signUpConfirmErr.send(e);
      });
  });

  app.ports.resendConfirmationCode.subscribe((username: string) => {
    Auth.resendSignUp(username)
      .then(app.ports.resendConfirmationCodeOk.send)
      .catch(app.ports.resendConfirmationCodeErr.send);
  });

  app.ports.signOut.subscribe(() => {
    Auth.signOut()
      .then(app.ports.signOutOk.send)
      .catch(app.ports.signOutErr.send);
  });

  app.ports.requestRefreshToken.subscribe(() => {
    Auth.currentSession()
      .then((token) => token.getAccessToken())
      .then((token) => {
        app.ports.refreshToken.send({
          jwt: token.getJwtToken(),
          expires: token.getExpiration() * 1000,
        });
      });
  });

  app.ports.signInWithGoogle.subscribe(() => {
    Auth.federatedSignIn({ provider: CognitoHostedUIIdentityProvider.Google })
      .then(app.ports.signInWithGoogleSuccess.send)
      .catch(app.ports.signInWithGoogleError.send);
  });

  app.ports.forgotPassword.subscribe((username: string) => {
    Auth.forgotPassword(username)
      .then(app.ports.forgotPasswordOk.send)
      .catch(app.ports.forgotPasswordErr.send);
  });

  app.ports.forgotPasswordSubmit.subscribe(({ username, code, password }: { username: string, code: string, password: string }) => {
    Auth.forgotPasswordSubmit(username, code, password)
      .then(app.ports.forgotPasswordSubmitOk.send)
      .catch(app.ports.forgotPasswordSubmitErr.send)
  });

}

run();
