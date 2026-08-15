---
name: resume-bullet-writer
description: Write and revise truthful, HR-readable software engineering resume bullets for internship and new-grad applications. Use when drafting bullets from notes, improving existing bullets, tailoring experience or project bullets to one or more job descriptions, or reviewing bullet clarity and impact.
---

# Resume Bullet Writer

Write concise software engineering resume bullets that a recruiter without deep technical knowledge can quickly understand. Preserve relevant technical keywords without turning bullets into jargon or tool lists.

## Accepted input

Support either:

- existing bullets or a complete experience/project entry
- raw notes about work, projects, research, coursework, or leadership
- one job description, several related descriptions, or only a target role family
- internship or new-grad applications

When a job description is available, tailor to it. Otherwise, optimize for the stated role family. If the target level is unclear, infer it from the posting or ask whether the user is applying for internships or new-grad roles.

## Workflow

1. **Identify the target.** Extract the qualifications and recurring keywords from requirements, qualifications, and must-have sections. With multiple postings, rank repeated qualifications; for one application, prioritize that posting.
2. **Establish the facts.** Determine what the candidate did, how they did it, their level of ownership, and the result or reason. If the current repository clearly contains the referenced project, inspect its code, documentation, and tests instead of asking answerable questions.
3. **Resolve only material gaps.** Ask focused follow-up questions when missing facts would substantially improve the bullet. Do not delay a useful rewrite for optional details.
4. **Draft and rank.** Write one primary version of each bullet, put the most relevant and compelling bullets first, and remove repetition across a full entry.
5. **Check every claim.** Ensure the final wording is supported, understandable, relevant to the target, and not inflated.

## Bullet standard

Prefer this flexible structure:

> **Action + contribution + relevant method + result or reason**

The parts may overlap. A concrete purpose is valid when no measured outcome exists.

Each bullet should:

- open with a specific action and make the main contribution clear early
- use exact job-description terminology only when it truthfully describes the work
- explain technical work in language an HR reviewer can follow
- include technical tools only when they clarify the method or demonstrate a target qualification
- focus on one main contribution and remain one concise sentence
- use consistent resume tense and omit first-person pronouns
- distinguish individual ownership from collaboration accurately
- describe student projects honestly rather than presenting them as production or company work

For internship targeting, emphasize applied fundamentals, initiative, collaboration, and learning demonstrated through work. For new-grad targeting, emphasize ownership, implementation depth, shipped work, reliability, and broader contribution. Never suppress strong evidence merely because the candidate is a student.

## Metrics and impact

Never invent, estimate, embellish, or force a metric. Never put metric placeholders such as `[X%]` in a final bullet.

Use a number only when it is:

1. real and defensible,
2. relevant to the candidate's contribution, and
3. meaningful enough to improve the bullet.

Valid evidence may include measured performance, latency, throughput, reliability, usage, scale, test coverage, time saved, or another concrete outcome. If a likely meaningful measurement is missing, ask about it once. If none exists, state a truthful qualitative result or explain why the work was done.

Do not infer business impact from technical changes. For example, faster code does not automatically imply increased revenue, improved customer satisfaction, or reduced costs.

## Avoid

- keyword stuffing or unexplained acronyms
- long technology inventories
- vague claims such as “worked on,” “helped with,” or “responsible for” when a specific action is known
- inflated verbs such as “architected,” “spearheaded,” or “revolutionized” without matching scope
- unsupported claims about leadership, deployment, users, scale, or impact
- generic soft-skill claims without behavioral evidence
- repeating the same accomplishment across multiple bullets
- adding a metric merely to make a bullet look impressive

## Output

Unless the user requests another format, return:

### Revised bullets
- Provide polished, ready-to-paste bullets with no placeholders.

### Notes
- Include only brief, useful notes: material assumptions, unsupported claims removed, or one factual question that could unlock a stronger revision.

For JD-tailored batches, optionally add a short **Qualification coverage** section listing important supported keywords and important gaps. Do not claim qualifications the candidate has not demonstrated.

Provide alternatives or detailed explanations only when requested.
