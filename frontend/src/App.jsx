import { BrowserRouter, Routes, Route } from 'react-router-dom'
import LiveDataProvider from './providers/LiveDataProvider'
import Overview from './pages/Overview'
import Topology from './pages/Topology'
import Alerts   from './pages/Alerts'
import Flows    from './pages/Flows'
import Models   from './pages/Models'
import Research from './pages/Research'
import Settings from './pages/Settings'

export default function App() {
  return (
    <BrowserRouter>
      <LiveDataProvider>
        <Routes>
          <Route path="/"         element={<Overview />} />
          <Route path="/topology" element={<Topology />} />
          <Route path="/alerts"   element={<Alerts />}   />
          <Route path="/flows"    element={<Flows />}    />
          <Route path="/models"   element={<Models />}   />
          <Route path="/research" element={<Research />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </LiveDataProvider>
    </BrowserRouter>
  )
}
