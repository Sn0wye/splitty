import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { api, onUnauthorized, tokenStore } from '@/api/client';
import { shouldClearSession } from '@/auth/session';
import type { User } from '@/types';

type AuthValue = { user: User | null; loading: boolean; signedIn: boolean; signInDev: (email: string) => Promise<void>; signInGoogle: (code: string) => Promise<void>; signOut: () => Promise<void> };
const AuthContext = createContext<AuthValue | null>(null);
export function AuthProvider({ children }: { children: React.ReactNode }): React.JSX.Element {
  const [user, setUser] = useState<User | null>(null);
  const [signedIn, setSignedIn] = useState(false);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    onUnauthorized(() => { void tokenStore.clear(); setUser(null); setSignedIn(false); });
    void (async () => {
      try {
        if (await tokenStore.get()) {
          setSignedIn(true);
          setUser(await api.profile());
        }
      } catch (error) {
        if (shouldClearSession(error)) {
          await tokenStore.clear();
          setUser(null);
          setSignedIn(false);
        }
      } finally {
        setLoading(false);
      }
    })();
  }, []);
  const value = useMemo<AuthValue>(() => ({
    user, loading, signedIn,
    signInDev: async email => { const next = await api.devLogin(email); setUser(next); setSignedIn(true); },
    signInGoogle: async code => { const next = await api.googleLogin(code); setUser(next); setSignedIn(true); },
    signOut: async () => { await tokenStore.clear(); setUser(null); setSignedIn(false); }
  }), [loading, signedIn, user]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
export function useAuth(): AuthValue { const value = useContext(AuthContext); if (!value) throw new Error('useAuth must be used within AuthProvider'); return value; }
