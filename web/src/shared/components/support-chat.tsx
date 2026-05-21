"use client";

import { useEffect, useRef, useState } from "react";
import { findAnswer } from "@/shared/lib/support-kb";

type Message = {
  id: number;
  role: "user" | "bot";
  text: string;
};

const WELCOME_MESSAGE: Message = {
  id: 0,
  role: "bot",
  text: "Olá! Sou o assistente da EasyHealth. Como posso te ajudar hoje?",
};

function ChatIcon() {
  return (
    <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M8 10h.01M12 10h.01M16 10h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
    </svg>
  );
}

export function SupportChat() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([WELCOME_MESSAGE]);
  const [input, setInput] = useState("");
  const [nextId, setNextId] = useState(1);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (open) bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, open]);

  function sendMessage() {
    const text = input.trim();
    if (!text) return;

    const userMsg: Message = { id: nextId, role: "user", text };
    const answer = findAnswer(text);
    const botMsg: Message = { id: nextId + 1, role: "bot", text: answer };

    setMessages((prev) => [...prev, userMsg, botMsg]);
    setNextId((n) => n + 2);
    setInput("");
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") sendMessage();
  }

  return (
    <>
      {/* Floating button */}
      <button
        onClick={() => setOpen((o) => !o)}
        aria-label="Abrir chat de suporte"
        className="fixed bottom-24 right-4 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-primary-500 text-white shadow-lg transition hover:bg-primary-600 active:scale-95"
      >
        {open ? (
          <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        ) : (
          <ChatIcon />
        )}
      </button>

      {/* Chat panel */}
      {open && (
        <div
          className="fixed bottom-40 right-4 z-40 flex w-[min(340px,calc(100vw-2rem))] flex-col overflow-hidden rounded-2xl bg-white shadow-2xl"
          style={{ maxHeight: "60vh" }}
        >
          {/* Header */}
          <div className="flex items-center gap-3 bg-primary-500 px-4 py-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-white/20 text-white">
              <ChatIcon />
            </div>
            <div>
              <p className="text-sm font-semibold text-white">Suporte EasyHealth</p>
              <p className="text-xs text-primary-100">Assistente virtual</p>
            </div>
          </div>

          {/* Messages */}
          <div className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
            {messages.map((msg) => (
              <div
                key={msg.id}
                className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}
              >
                <div
                  className={`max-w-[85%] rounded-2xl px-3 py-2 text-sm leading-relaxed ${
                    msg.role === "user"
                      ? "bg-primary-500 text-white"
                      : "bg-gray-100 text-gray-800"
                  }`}
                >
                  {msg.text}
                </div>
              </div>
            ))}
            <div ref={bottomRef} />
          </div>

          {/* Input */}
          <div className="flex gap-2 border-t border-gray-100 px-3 py-3">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Digite sua dúvida..."
              className="flex-1 rounded-xl border border-gray-200 px-3 py-2 text-sm focus:border-primary-400 focus:outline-none"
            />
            <button
              onClick={sendMessage}
              disabled={!input.trim()}
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary-500 text-white disabled:opacity-40"
            >
              <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
              </svg>
            </button>
          </div>
        </div>
      )}
    </>
  );
}
