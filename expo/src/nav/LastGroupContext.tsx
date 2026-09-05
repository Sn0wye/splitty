import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { router } from 'expo-router';
import * as SecureStore from 'expo-secure-store';

const KEY = 'splitty.lastGroupId';

type LastGroupValue = {
  groupId: number | null;
  ready: boolean;
  setCurrentGroupId: (id: number | null) => Promise<void>;
  openGroup: (id: number, options?: { replace?: boolean }) => Promise<void>;
};

const LastGroupContext = createContext<LastGroupValue | null>(null);

export function LastGroupProvider({ children }: { children: React.ReactNode }): React.JSX.Element {
  const [groupId, setGroupId] = useState<number | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    void (async () => {
      const stored = await SecureStore.getItemAsync(KEY);
      const parsed = stored ? Number(stored) : NaN;
      setGroupId(Number.isInteger(parsed) ? parsed : null);
      setReady(true);
    })();
  }, []);

  const setCurrentGroupId = useCallback(async (id: number | null) => {
    setGroupId(id);
    if (id == null) await SecureStore.deleteItemAsync(KEY);
    else await SecureStore.setItemAsync(KEY, String(id));
  }, []);

  const openGroup = useCallback(async (id: number, options?: { replace?: boolean }) => {
    await setCurrentGroupId(id);
    if (options?.replace) router.replace(`/(tabs)/group/${id}`);
    else router.navigate(`/(tabs)/group/${id}`);
  }, [setCurrentGroupId]);

  const value = useMemo<LastGroupValue>(() => ({ groupId, ready, setCurrentGroupId, openGroup }), [groupId, openGroup, ready, setCurrentGroupId]);
  return <LastGroupContext.Provider value={value}>{children}</LastGroupContext.Provider>;
}

export function useLastGroup(): LastGroupValue {
  const value = useContext(LastGroupContext);
  if (!value) throw new Error('useLastGroup must be used within LastGroupProvider');
  return value;
}
