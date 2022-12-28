---
layout: post
title: GitHub Actions authorizing to AWS
date: '2022-12-28T11:09:01.000+0000'
author: Robert Elliot
tags:
---

Quick notes on integrating GitHub Actions with AWS. Mostly to try and distill
the GitHub documentation into its essentials.

Fuller details can be found in GitHub's documentation 
[About security hardening with OpenID Connect][1]
and specifically for AWS at [Configuring OpenID Connect in Amazon Web Services][2]

## Steps:

### In AWS IAM

1) Add an Identity Provider in AWS IAM
   - Provider: `token.actions.githubusercontent.com` 
   - Audience: `sts.amazonaws.com`

2) Create an IAM Role

3) Under **Permissions** add a policy granting whatever it is the role needs to do
   (can be an inline policy, whatever - this is a standard IAM role, specific to
   what you need to do, nothing to do with it being GitHub Actions that will do
   it).

4) Under **Trust relationships** add something like this:
   ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Federated": "<ARN of the token.actions.githubusercontent.com Identity Provider>"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
            "StringEquals": {
              "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
            },
            "StringLike": {
              "token.actions.githubusercontent.com:sub": "repo:<GitHub org or username>/*"
            }
          }
        }
      ]
    }
   ```
   The `StringLike` match is important - without it anyone who knows the ARN of
   the role could configure GitHub to authenticate as that role, but as they
   cannot change the `sub` that GitHub sends to AWS to authenticate you have
   complete control here of which repositories and branches / tags can assume
   this role. See [Configuring the OIDC trust with the cloud][3].

### In GitHub Action

1) Allow `id_token` write permission

   By default the GitHub Action cannot write an id_token, so you need (at a
   minimum) this at the top of your workflow file:
   ```yaml
   permissions:
     id-token: write
     contents: read
   ```
   **You may need further permissions for other actions!** See
   [Adding permissions settings][4] for more details / examples.

2) Add the following step to your job:
   ```yaml
   - name: configure aws credentials
     uses: aws-actions/configure-aws-credentials@v1
     with:
       role-to-assume: <ARN of the Role you created above>
       aws-region: ${{ env.AWS_REGION }}
   ```

And that's it, really.

[1]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
[2]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
[3]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#configuring-the-oidc-trust-with-the-cloud
[4]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#adding-permissions-settings
