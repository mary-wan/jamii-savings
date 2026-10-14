// Jamii Savings Integration - single pipeline: build, test, package, deploy.
//
// TARGET_ENV represents dev vs prod as separate, named environments (per the
// assignment requirement). Only "dev" is actually wired up to a running
// WSO2 MI / APIM pair in this assessment; selecting "prod" exercises the
// pipeline structure but intentionally skips real deployment, since no prod
// infrastructure exists. This keeps dev/prod as genuinely separate stages
// without inventing an unneeded second environment just to "look complete".
pipeline {
    agent any

    parameters {
        choice(name: 'TARGET_ENV', choices: ['dev', 'prod'], description: 'Deployment target environment')
    }

    environment {
        MI_HOST        = 'jamii-mi'
        AM_HOST        = 'jamii-am'
        MI_DEPLOY_PATH = '/home/wso2carbon/wso2mi-4.6.0/repository/deployment/server/carbonapps'
        CAR_FILE       = 'JamiiSavingsIntegration_1.0.0.car'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build MI Integration') {
            // Packages the 3 integrations into a single Carbon Application (.car).
            steps {
                dir('mi-integration') {
                    sh 'mvn -B -q clean install'
                }
                archiveArtifacts artifacts: 'mi-integration/target/*.car', fingerprint: true
            }
        }

        stage('Deploy MI Artifact (dev)') {
            when { expression { params.TARGET_ENV == 'dev' } }
            steps {
                // Hot-deploy: drop the .car into MI's deployment folder on the
                // running container and give it a few seconds to pick it up.
                sh """
                    docker cp mi-integration/target/${CAR_FILE} ${MI_HOST}:${MI_DEPLOY_PATH}/${CAR_FILE}
                    sleep 10
                """
            }
        }

        stage('Test MI Integrations (dev)') {
            // Functional smoke tests against the freshly deployed artifact,
            // calling MI directly (bypassing APIM) - success case + the
            // required error cases for all three integrations.
            when { expression { params.TARGET_ENV == 'dev' } }
            steps {
                sh "pwsh -File scripts/test-apis.ps1 -BaseUrl http://${MI_HOST}:8290"
            }
        }

        stage('Deploy/Update APIM APIs (dev)') {
            // Imports (or updates) all three APIs plus the API Product from
            // the apictl projects already committed in apim/apictl-project/.
            when { expression { params.TARGET_ENV == 'dev' } }
            steps {
                sh """
                    # apictl's OAuth2 client-registration call occasionally fails TLS
                    # verification on its very first attempt against a freshly-added
                    # environment (observed with api-product imports and fresh logins),
                    # but always succeeds on an immediate retry once cached locally.
                    # Each network-touching apictl call below is retried once so a
                    # single flaky attempt doesn't fail the whole deploy.
                    apictl add env dev \
                        --apim https://${AM_HOST}:9443 \
                        --registration https://${AM_HOST}:9443 \
                        --token https://${AM_HOST}:9443/oauth2/token \
                        --publisher https://${AM_HOST}:9443 \
                        --devportal https://${AM_HOST}:9443 \
                        --admin https://${AM_HOST}:9443 2>/dev/null || true

                    apictl login dev -u admin -p admin -k || (sleep 5 && apictl login dev -u admin -p admin -k)

                    apictl import api -f apim/apictl-project/accounts-balance-api --environment dev --update --rotate-revision -k --verbose \
                        || (sleep 5 && apictl import api -f apim/apictl-project/accounts-balance-api --environment dev --update --rotate-revision -k --verbose)

                    apictl import api -f apim/apictl-project/customers-api --environment dev --update --rotate-revision -k --verbose \
                        || (sleep 5 && apictl import api -f apim/apictl-project/customers-api --environment dev --update --rotate-revision -k --verbose)

                    apictl import api -f apim/apictl-project/loans-eligibility-api --environment dev --update --rotate-revision -k --verbose \
                        || (sleep 5 && apictl import api -f apim/apictl-project/loans-eligibility-api --environment dev --update --rotate-revision -k --verbose)

                    sleep 8
                    apictl import api-product -f apim/apictl-project/jamii-savings-api-product --environment dev --update-api-product --update-apis --import-apis --rotate-revision -k --verbose \
                        || (sleep 5 && apictl import api-product -f apim/apictl-project/jamii-savings-api-product --environment dev --update-api-product --update-apis --import-apis --rotate-revision -k --verbose)

                    apictl logout dev || true
                """
            }
        }

        stage('Post-Deploy Gateway Verification (dev)') {
            // Proves the APIs are actually reachable through the APIM
            // gateway (not just imported) by obtaining a real OAuth2 token
            // and calling each API's gateway URL once.
            when { expression { params.TARGET_ENV == 'dev' } }
            steps {
                sh """
                    apictl login dev -u admin -p admin -k || (sleep 5 && apictl login dev -u admin -p admin -k)
                    set -e

                    # apictl prints its own error text into the same stream we
                    # capture, so a failed call can leave \$TOKEN holding an
                    # error message instead of staying empty -- a plain '-z'
                    # check can't tell that apart from a real token. Validate
                    # the JWT shape (two dots, no whitespace) and retry with
                    # backoff, discarding stderr noise from the capture.
                    get_token() {
                        name=\$1; version=\$2
                        attempt=1
                        while [ \$attempt -le 4 ]; do
                            candidate=\$(apictl get keys -n "\$name" -v "\$version" -e dev --provider admin -k 2>/dev/null | tr -d '\r\n ')
                            case "\$candidate" in
                                *.*.*) echo "\$candidate"; return 0 ;;
                            esac
                            attempt=\$((attempt + 1))
                            sleep 5
                        done
                        echo "Failed to obtain a valid token for \$name after retries" >&2
                        return 1
                    }

                    TOKEN=\$(get_token AccountsBalanceAPI 1.0.0)
                    STATUS=\$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer \$TOKEN" https://${AM_HOST}:8243/accounts/1.0.0/1000000001/balance)
                    echo "AccountsBalanceAPI gateway status: \$STATUS"
                    if [ "\$STATUS" != "200" ]; then echo "Gateway verification failed for AccountsBalanceAPI"; exit 1; fi

                    TOKEN=\$(get_token CustomersAPI 1.0.0)
                    STATUS=\$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer \$TOKEN" https://${AM_HOST}:8243/customers/1.0.0/1)
                    echo "CustomersAPI gateway status: \$STATUS"
                    if [ "\$STATUS" != "200" ]; then echo "Gateway verification failed for CustomersAPI"; exit 1; fi

                    TOKEN=\$(get_token LoansEligibilityAPI 1.0.0)
                    STATUS=\$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer \$TOKEN" -H "Content-Type: application/json" -X POST -d '{"customerId":1,"requestedAmount":50000}' https://${AM_HOST}:8243/loans/1.0.0/eligibility)
                    echo "LoansEligibilityAPI gateway status: \$STATUS"
                    if [ "\$STATUS" != "200" ]; then echo "Gateway verification failed for LoansEligibilityAPI"; exit 1; fi

                    apictl logout dev || true
                """
            }
        }

        stage('Production Deployment') {
            // Represents the prod environment as a distinct, named stage
            // without pretending it is actually connected.
            when { expression { params.TARGET_ENV == 'prod' } }
            steps {
                echo 'Production environment is not connected in this assessment setup.'
                echo 'This stage stands in for where a prod MI/APIM deploy would run once prod infrastructure exists; no action taken.'
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully for TARGET_ENV=${params.TARGET_ENV}"
        }
        failure {
            echo "Pipeline FAILED for TARGET_ENV=${params.TARGET_ENV} - see the failing stage log above."
        }
    }
}
