import React from 'react';
import { Redirect } from 'expo-router';
import { Loading } from '@/components/Screen';
import { useAuth } from '@/auth/AuthContext';

export default function Index(): React.JSX.Element {
  const { signedIn, loading } = useAuth();
  if (loading) return <Loading />;
  return signedIn ? <Redirect href="/(tabs)" /> : <Redirect href="/login" />;
}
