import express from "express";
import {
  addTask,
  updateTask,
  deleteTask,
  getAllTasks,
  getTaskById,
} from "../Controller/taskController.js";
// import { authMiddleware } from "../middleware/authMiddleware.js"; // if you have JWT

const router = express.Router();

router.post("/addtask",  addTask);
router.get("/gettask", getAllTasks);
router.get("/:id", getTaskById);
router.put("/:id",  updateTask);
router.delete("/:id",  deleteTask);

export default router;
