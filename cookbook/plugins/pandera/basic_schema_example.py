"""
Basic Schema Example
--------------------

In this example we'll show you how to use :ref:`pandera.SchemaModel <pandera:schema_models>`
to annotate dataframe inputs and outputs in your flyte tasks.

"""

import flytekitplugins.pandera
import pandas as pd
import pandera as pa
from flytekit import task, workflow
from pandera.typing import DataFrame, Series


# %%
# A Simple Data Processing Pipeline
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
# Let's first define a simple data processing pipeline in pure python.

def total_pay(df):
    return df.assign(total_pay=df.hourly_pay * df.hours_worked)

def add_id(df, id):
    return df.assign(worker_id=id)

def process_data():
    worker_id = 100
    df = pd.DataFrame({"hourly_pay": [12.0, 13.5, 10.1], "hours_worked": [30.5, 40.0, 41.75]})
    return add_id(df=total_pay(df=df), id=worker_id)

# %%
# As you can see, the ``process_data`` function is composed of two simpler functions:
# One that computes ``total_pay`` and another that simply adds an ``id`` column to
# a pandas dataframe.

# %%
# Defining DataFrame Schemas
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
# Next we define the schemas that provide type and statistical annotations
# for the raw, intermediate, and final outputs of our pipeline.

class InSchema(pa.SchemaModel):
    hourly_pay: Series[float] = pa.Field(ge=7)
    hours_worked: Series[float] = pa.Field(ge=10)

    @pa.check("hourly_pay", "hours_worked")
    def check_numbers_are_positive(cls, series: Series) -> Series[bool]:
        """Defines a column-level custom check."""
        return series > 0

    class Config:
        coerce = True

class IntermediateSchema(InSchema):
    total_pay: Series[float]

    @pa.dataframe_check
    def check_total_pay(cls, df: DataFrame) -> Series[bool]:
        """Defines a dataframe-level custom check."""
        return df["total_pay"] == df["hourly_pay"] * df["hours_worked"]

class OutSchema(IntermediateSchema):
    worker_id: Series[str] = pa.Field(allow_duplicates=False)

# %%
# Columns are specified as class attributes with a specified data type using the
# type-hinting syntax, and you can place additional statistical constraints on the
# values of each column using :py:func:`~pandera.model_components.Field`. You can also define custom validation functions
# by decorating methods with :py:func:`~pandera.model_components.check` (column-level checks) or
# :py:func:`~pandera.model_components.dataframe_check` (dataframe-level checks), which automatically make them
# class methods.
#
# Pandera uses inheritence to make sure that :py:class:`~pandera.model.SchemaModel` subclasses contain
# all of the same columns and custom check methods as their base class. Inheritance semantics
# apply to schema models so you can override column attributes or check methods in subclasses. This has
# the nice effect of providing an explicit graph of type dependencies as data
# flows through the various tasks in your workflow.


# %%
# Type Annotating Tasks and Workflows
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
# Finally, we can turn our data processing pipeline into a Flyte workflow
# by decorating our functions with the :py:func:`~flytekit.task` and :py:func:`~flytekit.workflow` decorators and
# annotating the inputs and outputs of those functions with the pandera schemas:

@task
def total_pay(df: DataFrame[InSchema]) -> DataFrame[IntermediateSchema]:
    return df.assign(total_pay=df.hourly_pay * df.hours_worked)

@task
def add_id(df: DataFrame[IntermediateSchema], id: str) -> DataFrame[OutSchema]:
    return df.assign(worker_id=id)

@workflow
def pandera_workflow(df: DataFrame[InSchema], worker_id: str) -> DataFrame[OutSchema]:
    return add_id(df=total_pay(df=df), id=worker_id)

if __name__ == "__main__":
    print(f"Running {__file__} main...")
    df = pd.DataFrame(
        {"hourly_pay": [12.0, 13.5, 10.1], "hours_worked": [30.5, 40.0, 41.75]}
    )
    result = pandera_workflow(df=df, worker_id="qwerty")
    print(f"Running wf(), returns dataframe\n{result}\n{result.dtypes}")


# %% Now your workflows and tasks are guarded against unexpected data at runtime!
