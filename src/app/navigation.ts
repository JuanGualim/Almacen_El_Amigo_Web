export type ActiveView = 'home' | 'inventory' | 'operations' | 'more' | 'sell'

export function viewFromLocation(): ActiveView {
  const value = window.location.hash.replace('#', '')
  return value === 'inventory' || value === 'operations' || value === 'more' || value === 'sell' ? value : 'home'
}
