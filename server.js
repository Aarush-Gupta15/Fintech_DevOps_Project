const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST || "localhost",
  user: process.env.DB_USER || "postgres",
  password: process.env.DB_PASSWORD || "postgres",
  database: process.env.DB_NAME || "fintech",
  port: parseInt(process.env.DB_PORT) || 5432,
});

// Health check - for liveness probe
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", uptime: process.uptime() });
});

// Readiness check - checks DB connection
app.get("/api/ready", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ready", db: "connected" });
  } catch (err) {
    res.status(503).json({ status: "not ready", db: "disconnected" });
  }
});

// Basic metrics endpoint
app.get("/api/metrics", (req, res) => {
  res.json({
    uptime: process.uptime(),
    memoryUsage: process.memoryUsage(),
    timestamp: new Date().toISOString(),
  });
});

app.get("/api/users", async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM users");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/users", async (req, res) => {
  const { name } = req.body;
  try {
    const result = await pool.query(
      "INSERT INTO users(name) VALUES($1) RETURNING *",
      [name]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => console.log("Backend running on port 3000"));