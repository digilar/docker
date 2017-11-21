# docker
Utility project for common Docker components such as base images etc.

__General Strategy for Secrets/Properties in our Docker Swarms__

When it comes to how to handle secrets and Docker there’s been a lot happening over the last few years but it seems that the actual management of secrets is still somewhat lacking (at least in terms of usability). See Docker’s own docs for a more thorough walk-through. In particular, look at the key rotation mechanism.
Our recommended approach for now can be found at the bottom of this document.

Short and sweet summary of _docker secret create_:

http://training.play-with-docker.com/swarm-compose-secrets/

The bigger picture:

https://docs.docker.com/engine/swarm/secrets/#how-docker-manages-secrets
https://docs.docker.com/engine/swarm/secrets/#example-rotate-a-secret

__The different aspects of secret management__

Remember, docker secret * is a fairly new concept tailor made for handling sensitive data within a Swarm in a secure manner and the __concept only exists within a Swarm__. 

- How to access secret key/values from a container. A generic approach to this problem is the whole idea of docker secrets (remember, a Swarm-only concept), secret key/values are mounted by the Swarm and during service create/update, a service is then given access to one ore more secrets (exposed as a virtual in-mem file system under /run/secrets/my_secret_key). The secrets are Swarm-wide but a service can only access the secrets that is has been given explicit access to (example docker service create —secret mySecretKey). 

- How to inject secrets into the Swarm (where to run docker secret create…). Remember, this is done on Swarm-level, not project level. So when running a CI/CD system such as CircleCI, it’s not entirely clear when to run any add/update scripts of a secret. CircleCI runs on a push on a git repo, it is not clear what push should start a secret rotation. Remember, the secret values are NOT in git. Plus the complicated update/rotate scenario makes for hairy scripting. Basically a secret is immutable but can be rotated through a versioning scheme, but how do you know which secrets to update? Some approaches that people have tried is to look at an explicit naming of secret keys using a versioning scheme. So if a “newer” version exists, then the value should be rotated. There are also some metadata such as creation/modified dates that can be inspected for a secret but the scripts to get this working are pretty advanced and error prone. This could easily result in a scenario where some secrets are updated but some are not du to a failing script.

- Where do you keep the secret values? Cannot be in git and preferably you’d like some way of grouping secrets per service and/or environment much like a properties file does. If the values are not in git, then how do you detect a change of a value so that a CI/CD job can be run? The options that come to mind here are either to keep the secret values as env variables in CircleCI or in a (possibly encrypted) S3 bucket.

__Our Recommended Approach__

To keep things as simple as possible both with respect to readability/clarity and complexity a bucket on S3 holding property-files is recommended. Even though each service would have to download and parse a property file, the relative complexity is lower both in terms of scripting, updating secrets and step-debugging.
For development a local file can be used instead of downloading from S3. A common library can likely be developed so that each project won’t have to reimplement the same code. The only precaution that must be taken here is that the file downloaded from s3 MUST NOT be saved to disk locally as that would negate the whole purpose of trying to keep secrets secret… But S3 has client libraries for most languages and nodes is no exception. Something like the  code below should be enough:

~~~~
const fs = require('fs');

const aws = require('aws-sdk');
const s3 = new aws.S3({
	// The .trim() is just an extra precaution to make sure we never get any line feeds etc when reading secrets
	accessKeyId: fs.readFile('/run/secrets/aws_access_key_id’, 'utf8').trim(), 
	secretAccessKey:fs.readFile('/run/secrets/aws_secret_access_key’, 'utf8').trim()
});

var getParams = {
	// These would typically be env variables as they are not secret… 
   Bucket: process.env.MY_BUCKET_NAME, // your bucket name
   Key: 'abc.txt' // process.env.MY_PROPS_FILE
}

s3.getObject(getParams, function(err, data) {
    if (err) return err;

  // Parse your properties as JSON or any other format you choose and populate your properties needed in your service
  // BUT DON’T SAVE THIS TO LOCAL DISK IN THE CONTAINER AS THAT MAY LEAK THE SECRETS!!!!
  let propertiesAsString = data.Body.toString('utf-8'); // Use the encoding necessary
});
~~~~


__How to access S3 from the Swarm__

This is the bootstrap problem… IF the S3 bucket is not public and not on the same AWS VPC then we (most likely) need at least these secrets.
It is possible that one can relax the security and let requests come through is we’re on the same VPC (using some AWS access policy) without  the credentials but this will not work when running locally on Docker for Mac. But at least these secret are likely rotated very seldom and they really are secrets.
It can be debated whether properties such as user name, connection pool configs etc really are secret, but if we keep all config in the same file we can handle everything the same, again for simplicity.


__Deploying Services__

From the deploy.sh script we need to add:

~~~~
docker service create \
	--name my_service \
	--secret aws_access_key_id \ <— Gives my_service access to the secret aws_access_key_id
	--secret aws_secret_access_key \
	--env MY_BUCKET_NAME=my_bucket \
	--env MY_PROPS_FILE=my_service.json.dev \
	my_service:1.0
~~~~

The same approach would then be used in a future docker stack deploy:

~~~~
version: ‘3.2’

services:
   my_service_name:
        image: my_service:1.0.3

   environment:
       MY_BUCKET_NAME: my_bucket
       MY_PROPS_FILE: my_service.json.prod <-- Note that we use a different file here
       
   secrets:
        - aws_access_key_id
        - aws_secret_access_key


   my_service_name_2:
        image: my_service_2:2.0.12
	.
	.

secrets:
   aws_access_key_id:
        external: true	<— Secret MUST already exist in swarm for deploy to succeed
   aws_secret_access_key:
        external: true
~~~~


