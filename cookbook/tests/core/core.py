import os
import subprocess

import pytest
from flytekit.common import launch_plan
from flytekit.models import literals
from flytekit.models.common import NamedEntityIdentifier as _NamedEntityIdentifier

PROJECT = "flytesnacks"
DOMAIN = "development"
VERSION = os.getpid()

# These are the names of the launch plans (workflows) kicked off in the run.sh script
# This is what we'll be looking for in Admin.
EXPECTED_EXECUTIONS = [
    'core.control_flow.dynamics.wf',
    'core.control_flow.map_task.my_map_workflow',
]

TEST_MANIFEST = {
    'core.control_flow.dynamics.wf': {
        'input': {},
        'output': {},
    },
    'core.control_flow.map_task.my_map_workflow': {
        'input': {},
        'output': {},
    }
}


@pytest.fixture(scope="session")
def flyte_workflows_register(request):
    subprocess.check_call(
        f"flytectl register example -p {PROJECT} -d {DOMAIN} --version=v{VERSION}",
        shell=True,
    )


def test_register_workflow_count(flyteclient, flyte_workflows_register, capsys_suspender):
    with capsys_suspender():
        workflows = flyteclient.list_workflows_paginated(identifier=_NamedEntityIdentifier(project=PROJECT, domain=DOMAIN),limit=100, token=None)
        assert workflows[0].__len__() == 40


def test_verify_register_workflow(flyteclient, flyte_workflows_register, capsys_suspender):
    with capsys_suspender():
        workflows = flyteclient.list_workflows_paginated(identifier=_NamedEntityIdentifier(project=PROJECT, domain=DOMAIN),limit=100, token=None)
        expected_register_workflow_count = len(TEST_MANIFEST)
        for x in range(workflows[0].__len__()):
            for y in TEST_MANIFEST:
                if workflows[0][x].id.name == y:
                    expected_register_workflow_count -= 1
        assert expected_register_workflow_count == 0


def run_launch_plan(name,test):
    lp = launch_plan.SdkLaunchPlan.fetch(
        PROJECT, DOMAIN, name, VERSION
    )
    execution = lp.launch_with_literals(
        PROJECT, DOMAIN, literals.LiteralMap(test["input"])
    )
    print(execution.id.name)


def test_launch_plans(flyteclient,flyte_workflows_register):
    for x in TEST_MANIFEST:
        print(f"Running launch plan for {x}")
        run_launch_plan(TEST_MANIFEST[x])
