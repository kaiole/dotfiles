// A highlighting fixture, not application code. Expectations follow each line.
#include <coroutine>
#include <cstdio>
#include <typeinfo>
#define SAMPLE_VALUE 42 // keyword:#define; constant:SAMPLE_VALUE

namespace sample { // keyword:namespace; type:sample
using Count = unsigned long; // keyword:using; type:Count,unsigned,long

template <typename T> // keyword:template,typename; type:T
concept Numeric = requires(T value) { value + 1; }; // keyword:concept,requires; type:Numeric,T; parameter:value

template <class T> // keyword:template,class; type:T
struct Box final { // keyword:struct,final; type:Box
public: // keyword:public
    T member{}; // type:T; member:member
    Box() noexcept = default; // function:Box; keyword:noexcept,default
    explicit(true) Box(T value) noexcept : member(value) {} // keyword:explicit,true,noexcept; function:Box; type:T; parameter:value; member:member
    Box(const Box&) = delete; // function:Box; keyword:const,delete
    ~Box() noexcept {} // function:Box; keyword:noexcept
    Box& operator=(Box&&) = default; // keyword:operator,default; type:Box
    [[nodiscard]] T get() const noexcept { return this->member; } // keyword:nodiscard,const,noexcept,return,this; type:T; function:get; member:member
    static constexpr bool enabled = true; // keyword:static,constexpr,true; type:bool; member:enabled
    bool is_self(const Box* value) const { return this == value; } // type:bool,Box; function:is_self; keyword:const,return,this; parameter:value
};

enum class State { ready, done }; // keyword:enum,class; type:State; constant:ready,done
struct Base { virtual ~Base() = default; }; // keyword:struct,virtual,default; type:Base
struct Derived : Base { ~Derived() override = default; }; // keyword:struct,override,default; type:Derived,Base

consteval int immediate() { return 1; } // keyword:consteval,return; type:int; function:immediate; constant:1
constexpr int context() { // keyword:constexpr; type:int; function:context
    if constexpr (true) { return 1; } else { return 2; } // keyword:if,constexpr,true,return,else; constant:1,2
}
constinit int initialized = immediate(); // keyword:constinit; type:int; variable:initialized; call:immediate
alignas(16) thread_local int aligned = 0; // keyword:alignas,thread_local; type:int; variable:aligned; constant:16,0
static_assert(sizeof(int) > 0); // keyword:static_assert,sizeof; type:int; constant:0

int add(int left, int right) { return left + right; } // type:int; function:add; parameter:left,right; keyword:return; punctuation:+

void exercise() { // type:void; function:exercise
    Box<int> box; // type:Box,int; variable:box
    Box<int> copy(1); // type:Box,int; variable:copy
    auto result = box.get(); // type:auto; variable:result,box; call:get
    bool safe = noexcept(box.get()); // type:bool; variable:safe,box; keyword:noexcept; call:get
    auto heap = new int(1); // type:auto,int; variable:heap; keyword:new; constant:1
    delete heap; // keyword:delete; variable:heap
    int final = 1; // type:int; variable:final; constant:1
    int override = final; // type:int; variable:override,final
    int module = override; // type:int; variable:module,override
    int import = module; // type:int; variable:import,module
    auto lambda = [](int value) noexcept { return value; }; // type:auto,int; variable:lambda; parameter:value; keyword:noexcept,return
    int* pointer = nullptr; // type:int; variable:pointer; keyword:nullptr
    bool flag = false; // type:bool; variable:flag; keyword:false
    const volatile int count = SAMPLE_VALUE; // keyword:const,volatile; type:int; variable:count; constant:SAMPLE_VALUE
    auto state = State::ready; // type:auto,State; variable:state; constant:ready
    double number = 3.14; // type:double; variable:number; constant:3.14
    char letter = 'x'; // type:char; variable:letter; string:'x'
    const char* text = "nullptr static_cast noexcept"; // keyword:const; type:char; variable:text; string:"nullptr static_cast noexcept"
    auto source = __FILE__; // type:auto; variable:source; builtin:__FILE__
    int line = __LINE__; // type:int; variable:line; builtin:__LINE__
    auto stream = stdin; // type:auto; variable:stream; builtin:stdin
    auto cast = static_cast<int>(number); // type:auto,int; variable:cast,number; keyword:static_cast
    auto cast2 = reinterpret_cast<void*>(pointer); // type:auto,void; variable:cast2,pointer; keyword:reinterpret_cast
    auto cast3 = const_cast<char*>(text); // type:auto,char; variable:cast3,text; keyword:const_cast
    Base* base = nullptr; // type:Base; variable:base; keyword:nullptr
    auto cast4 = dynamic_cast<Derived*>(base); // type:auto,Derived; variable:cast4,base; keyword:dynamic_cast
    const auto& info = typeid(box); // keyword:const,typeid; type:auto; variable:info,box
    auto alignment = alignof(int); // type:auto,int; variable:alignment; keyword:alignof
    using Result = decltype(result); // keyword:using,decltype; type:Result; variable:result
    if (flag and not pointer) { result = add(result, 1); } // keyword:if,and,not; variable:flag,pointer,result; call:add; constant:1
    flag = flag or false; // keyword:or,false; variable:flag
    result = result bitand count bitor 1 xor 2; // keyword:bitand,bitor,xor; variable:result,count; constant:1,2
    result = compl result; // keyword:compl; variable:result
    result and_eq 1; result or_eq 2; result xor_eq 3; // keyword:and_eq,or_eq,xor_eq; variable:result; constant:1,2,3
    flag = result not_eq 0; // keyword:not_eq; variable:flag,result; constant:0
    std::puts(text); // type:std; call:puts; variable:text
    for (int index = 0; index < count; ++index) { continue; } // keyword:for,continue; type:int; variable:index,count; constant:0
    while (flag) { break; } // keyword:while,break; variable:flag
    do { flag = true; } while (false); // keyword:do,true,while,false; variable:flag
    switch (state) { case State::ready: break; default: break; } // keyword:switch,case,break,default; type:State; variable:state; constant:ready
    try { throw 1; } catch (...) {} // keyword:try,throw,catch; constant:1
    // this nullptr static_assert operator noexcept must remain comments.
}

struct Task { // keyword:struct; type:Task
    struct promise_type { // keyword:struct; type:promise_type
        Task get_return_object() { return {}; }
        std::suspend_never initial_suspend() noexcept { return {}; }
        std::suspend_never final_suspend() noexcept { return {}; }
        void return_void() {}
        void unhandled_exception() {}
        std::suspend_never yield_value(int) { return {}; }
    };
};
Task coroutine() { // type:Task; function:coroutine
    co_await std::suspend_never{}; // keyword:co_await; type:std,suspend_never
    co_yield 1; // keyword:co_yield; constant:1
    co_return; // keyword:co_return
}
} // namespace sample
