Ex_doc server design
====================

The ex_doc server is a storage system for documentation. Clients can connect to
it using the normal Erlang communication and store new documentation or query
the existing documentation.

All server related code lives under `ExDoc.Server`.

Model
-----

The server considers documentation to have a tree shape:

    Project name
        Project version
            Normal module
                Type
                Function
                Macro
            Record
            Protocol

The project name and version are passed to the server when storing documentation
and should correspond to the `app` and `version` values in the project section
of the mix file of the project.

Processes
---------

This is the process tree for the server (* and + mean 0 or more and 1 or more
instances respectively):

    RootSupervisor
        QuerySupervisor
            QueryManager (:exdoc_query)
            QueryWorkerSupervisor
                QueryWorker+
        IngestSupervisor
            IngestManager (:exdoc_ingest)
            IngestWorkerSupervisor
                IngestWorker*

There are two main branches corresponding to the two main tasks: querying
documentation and storing new documentation ("ingest"). Clients will connect to
one of the manager nodes using their globally registered name (`:exdoc_query`,
`:exdoc_ingest`).

Query
-----

The query manager supports a range of queries such as:

* Give me a list of all documented projects.
* Give me info about a specific project.
* Give me info about all documented versions of a project.
* Give me a list of all modules in a project.
* Give me info about a specific module in a project.
* Give me a list of all functions in a module.
* Give me info about a specific function in a module.

Essentially the basic set of queries is what you'd get if you just generate the
basic REST calls for a tree of the form
`/project_name/project_version/module/function`.

This is of course not all that helpful but the idea is that the server will
later be expanded to support search.

The query manager internally just defers queries to one of the query workers and
returns the reply when it comes in.

Ingest
------

The ingest manager is very simple: it just has one call
`start_ingest(project_name, project_version, project_info)`.
Whenever a client wants to store documentation it calls `start_ingest` and
passes information about the project (info contains any additional information
such as source URL and description). The ingest manager then starts a new ingest
worker and returns the pid of it.

The ingest workers have two methods:

* `store_module(module_node)`
* `commit()`

When `commit()` is called the updated application is stored in the database and
the worker terminates. The worker links itself to the process that called
`start_ingest` and if that process terminates the worker terminates as well (no
information is inserted into the database).
