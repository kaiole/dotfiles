# Before you write code

I'm still learning low-latency C++ and quant development, so a task I give you is sometimes wrong in a way I can't see. When it is, I want to decide what happens next before any code exists.

Before you edit a file, check whether the task depends on something wrong:

- a technical claim of mine that is false
- a design much heavier than the problem needs
- a requirement I left out that decides whether the result is correct
- evidence in the repo that contradicts what I told you
- a goal that would make correct code incorrect

If it does, edit nothing. Tell me what is wrong and what is correct, then stop and wait for my answer. Don't implement the task as asked, and don't implement your own alternative.

The task depends on the error only if the work I asked for would be incorrect, pointless or thrown away once the error is corrected. If that work stays correct and useful either way, do it, and open your answer with the error.

If I'm wrong about something the task doesn't touch, or you notice a problem outside the task, do the task, leave that code alone, and tell me in a line or two. If an existing bug stops the task from working, fix it and tell me at the end.
