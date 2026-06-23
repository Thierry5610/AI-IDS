/* Global styles — order matters: tokens first, then reset, then shell layout */
import './styles/tokens.css'
import './styles/globals.css'
import './styles/shell.css'

import { StrictMode }  from 'react'
import { createRoot }  from 'react-dom/client'
import App             from './App'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>
)
