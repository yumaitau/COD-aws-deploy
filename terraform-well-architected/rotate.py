import json
import os
import re
import secrets
import string

import boto3


def handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]
    client = boto3.client("secretsmanager")
    if step == "createSecret":
        create_secret(client, arn, token)
    elif step == "setSecret":
        set_secret(client, arn, token)
    elif step == "testSecret":
        return
    elif step == "finishSecret":
        finish_secret(client, arn, token)
    else:
        raise ValueError(f"unsupported rotation step: {step}")


def _password():
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(28))


def _with_password(url, password):
    return re.sub(r"(postgresql://[^:]+:)[^@]+(@)", rf"\1{password}\2", url, count=1)


def create_secret(client, arn, token):
    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        return
    except client.exceptions.ResourceNotFoundException:
        pass
    pending = dict(current)
    password = _password()
    pending["POSTGRES_PASSWORD"] = password
    pending["DATABASE_URL"] = _with_password(current["DATABASE_URL"], password)
    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(pending),
        VersionStages=["AWSPENDING"],
    )


def set_secret(client, arn, token):
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")[
            "SecretString"
        ]
    )
    boto3.client("rds").modify_db_instance(
        DBInstanceIdentifier=os.environ["DB_INSTANCE_ID"],
        MasterUserPassword=pending["POSTGRES_PASSWORD"],
        ApplyImmediately=True,
    )


def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)
    for version, stages in metadata.get("VersionIdsToStages", {}).items():
        if "AWSCURRENT" in stages and version != token:
            client.update_secret_version_stage(
                SecretId=arn,
                VersionStage="AWSCURRENT",
                MoveToVersionId=token,
                RemoveFromVersionId=version,
            )
            break
    ecs = boto3.client("ecs")
    cluster = os.environ["ECS_CLUSTER"]
    for service in os.environ["ECS_SERVICES"].split(","):
        ecs.update_service(cluster=cluster, service=service, forceNewDeployment=True)
