# agent-swarm

Kernel-level observation and guarding of AI agent swarms running on Kubernetes.

## Language

**Agent**:
A workload that acts autonomously on behalf of a task — running tools, touching files, calling the network.
_Avoid_: bot, worker (when meaning any agent)

**Mock Agent**:
An **Agent** stand-in that, for each **Task** it receives, plays the matching **Scenario** instead of calling an LLM, so it costs no tokens. Occupies exactly the same slot a real **Agent** would.
_Avoid_: fake agent, stub

**Swarm**:
A coordinated group of **Agents**: one **Orchestrator** handing tasks to many **Workers**.

**Orchestrator**:
The **Agent** in a **Swarm** that splits work and hands tasks to **Workers**.

**Worker**:
An **Agent** in a **Swarm** that carries out tasks handed to it by the **Orchestrator**.

**Goal**:
What a **Swarm** is asked to achieve, given to its **Orchestrator** from outside (a human or CI). The **Orchestrator** splits a Goal into **Tasks**. A real **Orchestrator** reads it as a prompt; a **Mock Agent** Orchestrator reads it as the name of a plan of **Scenarios**.
_Avoid_: job, mission, run

**Task**:
A unit of work the **Orchestrator** hands to a **Worker**. A real **Agent** reads it as a prompt; a **Mock Agent** reads it as the name of a **Scenario** to play.
_Avoid_: job, request

**Lost Task**:
A **Task** whose **Worker** stopped mid-way (typically killed by a **Guardrail**). A Lost Task is never retried.

**Adapter**:
A thin shim that lets a real **Agent** occupy the **Agent** slot by translating **Tasks** into the Agent's own input and its results back.

**Workspace**:
The one place an **Agent** is allowed to write. Writing anywhere else is misbehaviour.

**Scenario**:
A scripted sequence of actions a **Mock Agent** performs. Either **benign** (ordinary agent work) or **rogue** (misbehaviour such as exfiltration or privilege escalation).

**Approved Destination**:
A network destination an **Agent** is allowed to reach. Reaching anything else is misbehaviour.

**Outside World**:
The stand-ins for everything beyond the cluster: an approved external service, and an **Exfil Sink** playing the attacker. Tests never touch the real internet.

**Exfil Sink**:
The **Outside World** stand-in for an attacker's server. Never an **Approved Destination**; records whatever reaches it, so "nothing arrived" can be proven.

**Guardrail**:
A kernel-level rule that blocks or kills an **Agent** action, as opposed to merely observing it.

## Relationships

- A **Swarm** has exactly one **Orchestrator** and one or more **Workers**
- A **Goal** is split into one or more **Tasks**; each **Task** is taken by exactly one **Worker**, whichever is free
- A **Task** ends **succeeded**, **failed**, or **lost**
- A **Mock Agent** plays one **Scenario** per **Task**, and may play many over its life
- Mock and real **Agents** receive the same **Tasks**; nothing else about the slot differs
- A **rogue** **Scenario** is expected to trip at least one **Guardrail**
- Every **Swarm** runs benign **Scenarios** alongside rogue ones: a **Guardrail** that breaks benign work is a defect
- A **Guardrail** never distinguishes a **Mock Agent** from a real **Agent**

## Flagged ambiguities

- "monitor" was used for both observing and enforcing — resolved: observing is **monitoring**, enforcing is a **Guardrail**.
