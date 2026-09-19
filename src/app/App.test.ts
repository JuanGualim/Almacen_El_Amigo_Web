import { afterEach, describe, expect, it } from 'vitest'
import { viewFromLocation } from './navigation'

afterEach(() => { window.location.hash = '' })

describe('hash navigation', () => {
  it('maps a deferred secondary module to its route', () => {
    window.location.hash = 'more'
    expect(viewFromLocation()).toBe('more')
  })

  it('returns to the safe home route for an unknown hash', () => {
    window.location.hash = 'unsupported'
    expect(viewFromLocation()).toBe('home')
  })
})
