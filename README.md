# Restaurant Dialogue Flowcharts

This document contains three Mermaid flowcharts describing the restaurant interaction logic, drink ordering and confirmation flow, and implementation rules.

---

## 1. Customer Intent and Order Flow

```mermaid
flowchart TD
    START([Customer interaction]) --> GREET["Greet customer"]
    GREET --> ASK["Ask what the customer would like"]

    ASK --> INTENT{"Customer intent?"}

    INTENT -->|Order food| FOOD["Take food order"]
    INTENT -->|Order drinks| DRINKS["Take drink order"]
    INTENT -->|Ask a question| QUESTION["Answer customer question"]
    INTENT -->|Request assistance| HANDOFF["Hand off to waiter"]

    FOOD --> CONFIRM["Confirm order"]
    DRINKS --> CONFIRM
    QUESTION --> ASK
    HANDOFF --> END([End interaction])

    CONFIRM --> MORE{"Anything else?"}
    MORE -->|Yes| ASK
    MORE -->|No| END
```

---

## 2. Drinks, Confirmation and Order Revisions

```mermaid
flowchart TD
    START([Drink ordering]) --> MENU["Present available drinks"]
    MENU --> SELECT["Customer selects a drink"]
    SELECT --> CHECK{"Drink available?"}

    CHECK -->|Yes| ADD["Add drink to order"]
    CHECK -->|No| ALTERNATIVE["Suggest an alternative"]
    ALTERNATIVE --> SELECT

    ADD --> CONFIRM["Confirm drink selection"]
    CONFIRM --> REVISION{"Customer wants to revise?"}

    REVISION -->|Yes| CHANGE["Modify drink selection"]
    CHANGE --> CONFIRM

    REVISION -->|No| FINISH["Finalize drink order"]
    FINISH --> END([Return to main order flow])
```

---

## 3. Implementation Rules

```mermaid
flowchart TD
    START([Incoming customer input]) --> PARSE["Parse customer input"]
    PARSE --> VALIDATE{"Input understood?"}

    VALIDATE -->|No| CLARIFY["Ask for clarification"]
    CLARIFY --> PARSE

    VALIDATE -->|Yes| CLASSIFY["Classify intent"]
    CLASSIFY --> ROUTE{"Determine action"}

    ROUTE -->|Food order| FOOD["Food-order handler"]
    ROUTE -->|Drink order| DRINK["Drink-order handler"]
    ROUTE -->|Question| FAQ["Question handler"]
    ROUTE -->|Assistance| HANDOFF["Human handoff"]

    FOOD --> STATE["Update order state"]
    DRINK --> STATE
    FAQ --> RESPONSE["Generate response"]
    HANDOFF --> RESPONSE

    STATE --> RESPONSE
    RESPONSE --> OUTPUT["Send response to customer"]
    OUTPUT --> CONTINUE{"Interaction complete?"}

    CONTINUE -->|No| START
    CONTINUE -->|Yes| END([Finish])
```
