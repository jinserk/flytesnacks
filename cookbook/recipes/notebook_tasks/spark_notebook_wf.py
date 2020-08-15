import os

from flytekit.contrib.notebook.tasks import spark_notebook
from flytekit.sdk.tasks import inputs, outputs
from flytekit.sdk.types import Types
from flytekit.sdk.workflow import workflow_class, Input

interactive_spark = spark_notebook(
    notebook_path=os.path.abspath(__file__),
    inputs=inputs(partitions=Types.Integer),
    outputs=outputs(pi=Types.Float),
    )


@workflow_class
class FlyteNotebookSparkWorkflow(object):
    partitions = Input(Types.Integer, default=100)
    out1 = interactive_spark(partitions=partitions)
