import { Amplify } from 'aws-amplify';
import { getConfig } from '../config';

let configured = false;

export function configureAmplify() {
  if (configured) {
    return;
  }

  const { cognitoRegion, cognitoUserPoolId, cognitoAppClientId } = getConfig();

  if (!cognitoRegion || !cognitoUserPoolId || !cognitoAppClientId) {
    console.warn('Cognito configuration is incomplete. Authentication will be unavailable.');
    configured = true;
    return;
  }

  Amplify.configure({
    Auth: {
      region: cognitoRegion,
      userPoolId: cognitoUserPoolId,
      userPoolWebClientId: cognitoAppClientId,
      mandatorySignIn: true,
    },
  });

  configured = true;
}
