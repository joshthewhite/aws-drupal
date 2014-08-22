# Drupal Enterprise Installer for AWS

A utility to spin up an enterprise ready Drupal instance on AWS. Documentation and cleanup coming soon.

## Requirements

The only requirement of this application is [Bundler](http://bundler.io). All other dependencies can be installed with:

    bundle install

## Basic Configuration

You need to set up your AWS security credentials before the sample code is able
to connect to AWS. You can do this by creating a file named "credentials" at ~/.aws/ 
(C:\Users\USER_NAME\.aws\ for Windows users) and saving the following lines in the file:

    [default]
    aws_access_key_id = <your access key id>
    aws_secret_access_key = <your secret key>

See the [Security Credentials](http://aws.amazon.com/security-credentials) page
for more information on getting your keys.

## Running the S3 sample

    ruby drupal.rb
